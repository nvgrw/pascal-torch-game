PROGRAM GameProject;
{ NOTE: Please run on DOSBox with 52000 cycles or more }
USES CRT, DOS;
CONST
    GameFieldWidth = 60;
    GameFieldHeight = 48;
    LightCalculationInterval = 36; { 21 with rad 8, 36 with rad 14}
    MonsterLimit = 25;
TYPE
    Vector = RECORD
        X, Y: INTEGER;
    END;
    PlayerRecord = RECORD
        Position: VECTOR;
        DeltaPosition: VECTOR;
        Health: INTEGER;
        Bearing: REAL;
        Radius, FOV: INTEGER;
    END;
    Tile = RECORD
        Character: CHAR;
        Color, BackgroundColor: BYTE;
    END;
    Time = RECORD
        Hour, Minute, Second, HSecond: WORD;
    END;

    GameField = ARRAY[1..GameFieldWidth, 1..GameFieldHeight] OF Tile;
    MonsterVector = ARRAY[1..MonsterLimit] OF Vector;
CONST
    { Tiles }
        { Functional Tiles }
        EnvironmentTile: Tile = (Character: CHR(219); Color: DarkGray; BackgroundColor: Black);
        WallTile: Tile = (Character: CHR(219); Color: Yellow; BackgroundColor: Black);
        MonsterTile: Tile = (Character: CHR(254); Color: LightRed; BackgroundColor: Red);

        PlayerTile: Tile = (Character: CHR(254); Color: LightGreen; BackgroundColor: Blue);
        DarkTile: Tile = (Character: CHR(219); Color: Black; BackgroundColor: Black);

        { Representative Tiles }
        EmptyTile: Tile = (Character: CHR(0); Color: Blink; BackgroundColor: Magenta);
        LightTile: Tile = (Character: CHR(0); Color: White; BackgroundColor: Black);
VAR
    { Utility }
    Ch: CHAR;
    I, J{, K, L}: INTEGER;

    { Statekeeping }
    GameRunning: BOOLEAN;
    OriginalMode: INTEGER;

    Cycles, WorkingCycles: WORD;
    LastTime, CurrentTime: TIME;

    { Other }
    Player: PlayerRecord;
    Field: GameField;
    TorchCache: GameField;

    Monsters: MonsterVector;
    MonsterCount: WORD;

{ -- PROCEDURES & FUNCTIONS --}
    FUNCTION KeyDown: CHAR;
    VAR
        Ch: CHAR;
    BEGIN
        IF KEYPRESSED THEN
            KeyDown := READKEY
        ELSE
            KeyDown := CHR(0);
    END;

    FUNCTION Radians(Degrees: REAL): REAL;
    BEGIN
        Radians := Degrees * (Pi/180.0);
    END;

    PROCEDURE UpdateCurrentTime;
    BEGIN
        GetTime(CurrentTime.Hour, CurrentTime.Minute, CurrentTime.Second, CurrentTime.HSecond);
    END;

    FUNCTION TimestampFromTime(TheTime: TIME): LONGINT;
    VAR
        Result: LONGINT;
    BEGIN
        TimestampFromTime := (TheTime.Hour * 60 * 60 * 100) +
                            (TheTime.Minute * 60 * 100) +
                            (TheTime.Second * 100) +
                            (TheTime.HSecond);
    END;

    PROCEDURE Render(X, Y: INTEGER); FORWARD;
    PROCEDURE RenderGhost(X, Y: INTEGER; ActiveTile: Tile); FORWARD;

    PROCEDURE LoadLevel(Path: STRING); FORWARD;
    PROCEDURE InitGame;
    BEGIN
        CLRSCR;
        OriginalMode := LastMode;
        TEXTMODE(CO80 + Font8x8); {Make the whole thing square}

        { Initialise Player }
        WITH Player DO BEGIN
            WITH Position DO BEGIN
                X := 30;
                Y := 30;
            END;
            WITH DeltaPosition DO BEGIN
                X := 0;
                Y := 0;
            END;
            Health := 3;
            Bearing := -90.0;
            Radius := 14;
            FOV := 100;
        END;

        { Initialise game field }
        GOTOXY(1, 49);
        TEXTCOLOR(WHITE);
        TEXTBACKGROUND(BLACK);
        LoadLevel('LEV0.LEV');

        { Initialise torch cache }
        FOR I := 1 TO GameFieldHeight DO
            FOR J := 1 TO GameFieldWidth DO BEGIN
                TorchCache[J, I] := DarkTile;
                RenderGhost(J, I, DarkTile);
            END;

        RenderGhost(Player.Position.X, Player.Position.Y, PlayerTile);
    END;

    PROCEDURE LoadLevel(Path: STRING);
    VAR
        LevelFile: TEXT;
        Ch: CHAR;

        I, J: INTEGER;
    BEGIN
        ASSIGN(LevelFile, Path);
        RESET(LevelFile);

        MonsterCount := 0;
        FOR J := 1 TO GameFieldHeight DO BEGIN
            FOR I := 1 TO GameFieldWidth DO BEGIN
                READ(LevelFile, Ch);
                CASE Ch OF
                    '-' : Field[I, J] := EnvironmentTile;
                    '#' : Field[I, J] := WallTile;
                    'M' : BEGIN
                        Field[I, J] := MonsterTile;
                        MonsterCount := MonsterCount + 1;
                        Monsters[MonsterCount].X := I;
                        Monsters[MonsterCount].Y := J;
                    END;
                    '@' : BEGIN
                        Player.Position.X := I;
                        Player.Position.Y := J;
                        Field[I, J] := EnvironmentTile;
                    END;
                END;
            END;
            READ(LevelFile, Ch);
        END;

        CLOSE(LevelFile);
    END;

    PROCEDURE DeinitGame;
    BEGIN
        TEXTMODE(OriginalMode);
    END;

    PROCEDURE ResetPlayerDelta;
    BEGIN
        Player.DeltaPosition.X := 0;
        Player.DeltaPosition.Y := 0;
    END;

    PROCEDURE UpdatePlayer; FORWARD;
    PROCEDURE UpdateLight; FORWARD;
    PROCEDURE DetectInput;
    VAR
        V: VECTOR;
    BEGIN
        CASE KeyDown OF
            'q':
                GameRunning := FALSE;

            CHR(75), 'a': BEGIN {LEFT}
                Player.Bearing := Player.Bearing - 22.5;
                UpdateLight;
                END;

            CHR(72): BEGIN {UP}
                V.X := ROUND(COS(Radians(Player.Bearing)));
                V.Y := ROUND(SIN(Radians(Player.Bearing)));
                Player.DeltaPosition.X := V.X;
                Player.DeltaPosition.Y := V.Y;
                Player.Position.X := Player.Position.X + V.X;
                Player.Position.Y := Player.Position.Y + V.Y;
                UpdatePlayer;
                END;

            CHR(77), 'd': BEGIN {RIGHT}
                Player.Bearing := Player.Bearing + 22.5;
                UpdateLight;
                END;

            CHR(80): BEGIN {DOWN}
                V.X := ROUND(COS(Radians(Player.Bearing + 180.0)));
                V.Y := ROUND(SIN(Radians(Player.Bearing + 180.0)));
                Player.DeltaPosition.X := V.X;
                Player.DeltaPosition.Y := V.Y;
                Player.Position.X := Player.Position.X + V.X;
                Player.Position.Y := Player.Position.Y + V.Y;
                UpdatePlayer;
                END;
        END;
    END;

    FUNCTION TilesEqual(T1, T2: Tile): BOOLEAN;
    BEGIN
        TilesEqual := (T1.Character = T2.Character) AND (T1.Color = T2.Color) AND (T1.BackgroundColor = T2.BackgroundColor);
    END;

    PROCEDURE UpdateLight;
    VAR
        Look: VECTOR;
        I, J: INTEGER;
        NewTorchCache: GameField;
    BEGIN
        FOR I := 1 TO GameFieldHeight DO
            FOR J := 1 TO GameFieldWidth DO BEGIN
                NewTorchCache[J, I] := EmptyTile;
            END;

        { Recalculate light }
        FOR J := 0 TO LightCalculationInterval DO BEGIN
            FOR I := 1 TO Player.Radius DO BEGIN
                Look.X := ROUND(COS(Radians(
                    (Player.Bearing + ((Player.FOV/LightCalculationInterval)*J)) - (Player.FOV/2))) * I)
                    + Player.Position.X;
                Look.Y := ROUND(SIN(Radians(
                    (Player.Bearing + ((Player.FOV/LightCalculationInterval)*J)) - (Player.FOV/2))) * I)
                    + Player.Position.Y;

                IF (Look.X >= 1) AND (Look.X <= GameFieldWidth) AND (Look.Y >= 1) AND (Look.Y <= GameFieldHeight) THEN BEGIN
                    NewTorchCache[Look.X, Look.Y] := LightTile;
                    IF NOT(TilesEqual(NewTorchCache[Look.X, Look.Y], TorchCache[Look.X, Look.Y])) THEN
                        Render(Look.X, Look.Y);

                    IF NOT TilesEqual(Field[Look.X, Look.Y], EnvironmentTile) THEN
                        I := Player.Radius;
                END;
            END;
        END;

        { Remove light from where it was }
        FOR J := 1 TO GameFieldHeight DO
            FOR I := 1 TO GameFieldWidth DO BEGIN
                IF TilesEqual(NewTorchCache[I, J], EmptyTile)
                    AND TilesEqual(TorchCache[I, J], LightTile) THEN BEGIN
                    RenderGhost(I, J, DarkTile);
                END;
            END;

        { Fix player sprite }
        RenderGhost(Player.Position.X, Player.Position.Y, PlayerTile);
        TorchCache := NewTorchCache;
    END;

    PROCEDURE UpdatePlayer;
    VAR
        OldPosition: VECTOR;
    BEGIN
        WITH OldPosition DO BEGIN
            X := Player.Position.X - Player.DeltaPosition.X;
            Y := Player.Position.Y - Player.DeltaPosition.Y;
        END;

        IF TilesEqual(Field[Player.Position.X, Player.Position.Y], EnvironmentTile) AND
            ((Player.Position.X >= 1) AND (Player.Position.Y >= 1)) AND
            ((Player.Position.X <= GameFieldWidth) AND (Player.Position.Y <= GameFieldHeight)) THEN
            BEGIN
                RenderGhost(Player.Position.X, Player.Position.Y, PlayerTile);
                RenderGhost(OldPosition.X, OldPosition.Y, DarkTile);
                UpdateLight;
            END
        ELSE BEGIN
            Player.Position := OldPosition;
        END;
        ResetPlayerDelta;
    END;

    { Incomplete }
    {PROCEDURE UpdateMonsters;
    VAR
        I: INTEGER;
        CycleCounter: REAL;
    BEGIN
        TEXTCOLOR(WHITE);
        TEXTBACKGROUND(BLACK);
        GOTOXY(11, 50);

        IF Cycles > 0 THEN
            CycleCounter := WorkingCycles/Cycles
        ELSE
            CycleCounter := 0.0;
        WRITE('| ', MonsterCount, ' / ', MonsterLimit, ' MONSTERS ', CycleCounter:2:7);

        FOR I := 1 TO MonsterCount DO BEGIN

        END;
    END;}

    { Procedure for rendering/refreshing a tile at some coordinate }
    PROCEDURE Render(X, Y: INTEGER);
    VAR
        ActiveTile: Tile;
    BEGIN
        GOTOXY(X, Y);
        ActiveTile := Field[X, Y];
        TextColor(ActiveTile.Color);
        TextBackground(ActiveTile.BackgroundColor);
        WRITE(ActiveTile.Character);
    END;

    { Procedure for rendering a tile with a predefined style at some coordinate }
    PROCEDURE RenderGhost(X, Y: INTEGER; ActiveTile: Tile);
    BEGIN
        GOTOXY(X, Y);
        TextColor(ActiveTile.Color);
        TextBackground(ActiveTile.BackgroundColor);
        WRITE(ActiveTile.Character);
    END;
{ -- MAIN PROGRAM -- }
BEGIN
    GameRunning := TRUE;

    InitGame;
    UpdateLight;

    Cycles := 0;
    WorkingCycles := 0;

    UpdateCurrentTime;
    LastTime := CurrentTime;

    WHILE GameRunning DO BEGIN
        DetectInput;
        {UpdateMonsters;}

        { Calculate how many cycles are run per second }
        IF CurrentTime.Second = LastTime.Second THEN BEGIN
            WorkingCycles := WorkingCycles + 1;

            TEXTCOLOR(WHITE);
            TEXTBACKGROUND(BLACK);
            GOTOXY(9, 50);
            WRITE('A');
        END ELSE BEGIN
            LastTime := CurrentTime;
            Cycles := WorkingCycles;
            WorkingCycles := 0;

            TEXTCOLOR(WHITE);
            TEXTBACKGROUND(BLACK);
            GOTOXY(1, 50);
            WRITE(Cycles:7);

            GOTOXY(9, 50);
            WRITE('R');
        END;
        UpdateCurrentTime;
    END;
    DeinitGame;
END.
