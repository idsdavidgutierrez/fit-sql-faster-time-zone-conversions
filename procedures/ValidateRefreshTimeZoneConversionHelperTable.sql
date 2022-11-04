CREATE OR ALTER PROCEDURE #ValidateRefreshTimeZoneConversionHelperTable
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE
		@DidFunctionThrowError BIT,
		@DummyDate DATETIME2;

	IF EXISTS (
		SELECT 1
		FROM dbo.TZConvertDT2(NULL, N'UTC', N'UTC') c
		OUTER APPLY dbo.TZGetOffsetsDT2(NULL, N'UTC', N'UTC') o
		CROSS APPLY dbo.TZFormatDT2(NULL, N'UTC', N'UTC', o.OffsetMinutes, o.TargetOffsetMinutes) f
		WHERE c.ConvertedDate IS NOT NULL OR f.ConvertedDate IS NOT NULL
	)
	BEGIN
		THROW 3829210, N'NULL input handled incorrectly', 1;
	END;
	   
	SET @DidFunctionThrowError = 0;
	BEGIN TRY
		SELECT @DummyDate = c.ConvertedDateTime
		FROM dbo.TZConvertDT('20220101', N'UTC', N'FAKE TIME ZONE TO CAUSE ERROR') c
	END TRY
	BEGIN CATCH
		SET @DidFunctionThrowError = 1;
	END CATCH;
	IF @DidFunctionThrowError = 0
	BEGIN
		THROW 3829210, N'Bad time zone input handled incorrectly', 2;
	END;


	SET @DidFunctionThrowError = 0;
	BEGIN TRY
		SELECT @DummyDate = c.ConvertedDateTime
		FROM dbo.TZConvertDT('20220101', N'FAKE TIME ZONE TO CAUSE ERROR', N'UTC') c
	END TRY
	BEGIN CATCH
		SET @DidFunctionThrowError = 1;
	END CATCH;
	IF @DidFunctionThrowError = 0
	BEGIN
		THROW 3829210, N'Bad time zone input handled incorrectly', 3;
	END;

	SET @DidFunctionThrowError = 0;
	BEGIN TRY
		SELECT @DummyDate = c.ConvertedDateTime
		FROM dbo.TZFormatDT('20220101', N'FAKE TIME ZONE TO CAUSE ERROR', N'UTC', NULL, 0) c
	END TRY
	BEGIN CATCH
		SET @DidFunctionThrowError = 1;
	END CATCH;
	IF @DidFunctionThrowError = 0
	BEGIN
		THROW 3829210, N'Bad time zone input handled incorrectly', 4;
	END;
	
	SET @DidFunctionThrowError = 0;
	BEGIN TRY
		SELECT @DummyDate = c.ConvertedDateTime2
		FROM dbo.TZFormatDT('20220101', N'UTC', N'FAKE TIME ZONE TO CAUSE ERROR', NULL, NULL) c
	END TRY
	BEGIN CATCH
		SET @DidFunctionThrowError = 0;
	END CATCH;
	IF @DidFunctionThrowError = 1
	BEGIN
		THROW 3829210, N'Bad time zone input handled incorrectly', 5;
	END;

	SELECT
		h.SourceTimeZoneName,
		h.TargetTimeZoneName,
		dt.InputDT,
		dt.InputDTO,
		nt.NativeDTtoDTO
	FROM TimeZoneConversionHelper_CCI h
	CROSS APPLY (
		SELECT DATEADD(SECOND, CEILING(0.5 * DATEDIFF_BIG(SECOND, h.IntervalStart, h.IntervalEnd)), h.IntervalStart)
	) s (Input)
	CROSS APPLY (
		SELECT CAST(s.Input AS DATETIME),
		CAST(s.Input AS DATETIME2),
		SWITCHOFFSET(s.Input, h.TargetOffsetMinutes)
	) dt (InputDT, InputDT2, InputDTO)
	CROSS APPLY (
		SELECT dt.InputDT AT TIME ZONE SourceTimeZoneName AT TIME ZONE TargetTimeZoneName NativeDTtoDTO,
		dt.InputDT2 AT TIME ZONE SourceTimeZoneName AT TIME ZONE TargetTimeZoneName NativeDT2toDTO,
		dt.InputDTO AT TIME ZONE TargetTimeZoneName NativeDTO
	) nt
	CROSS APPLY dbo.TZConvertDT(dt.InputDT, h.SourceTimeZoneName, h.TargetTimeZoneName) c1
	CROSS APPLY dbo.TZConvertDT2(dt.InputDT2, h.SourceTimeZoneName, h.TargetTimeZoneName) c2
	CROSS APPLY dbo.TZConvertDTO(dt.InputDTO, h.TargetTimeZoneName) c3

	OUTER APPLY dbo.TZGetOffsetsDT(dt.InputDT, h.SourceTimeZoneName, h.TargetTimeZoneName) o1
	CROSS APPLY dbo.TZFormatDT(dt.InputDT, h.SourceTimeZoneName, h.TargetTimeZoneName, o1.OffsetMinutes, o1.TargetOffsetMinutes) f1
	OUTER APPLY dbo.TZGetOffsetsDT2(dt.InputDT2, h.SourceTimeZoneName, h.TargetTimeZoneName) o2
	CROSS APPLY dbo.TZFormatDT2(dt.InputDT2, h.SourceTimeZoneName, h.TargetTimeZoneName, o2.OffsetMinutes, o2.TargetOffsetMinutes) f2
	OUTER APPLY dbo.TZGetOffsetsDTO(dt.InputDTO, h.TargetTimeZoneName) o3
	CROSS APPLY dbo.TZFormatDTO(dt.InputDTO, h.TargetTimeZoneName, o3.OffsetMinutes, o3.TargetOffsetMinutes) f3

	WHERE	
	c1.ConvertedDate IS NULL OR c1.ConvertedDateTime IS NULL OR c1.ConvertedDateTime2 IS NULL OR c1.ConvertedDateTimeOffset IS NULL OR
	c2.ConvertedDate IS NULL OR c2.ConvertedDateTime IS NULL OR c2.ConvertedDateTime2 IS NULL OR c2.ConvertedDateTimeOffset IS NULL OR
	c3.ConvertedDate IS NULL OR c3.ConvertedDateTime IS NULL OR c3.ConvertedDateTime2 IS NULL OR c3.ConvertedDateTimeOffset IS NULL OR

	f1.ConvertedDate IS NULL OR f1.ConvertedDateTime IS NULL OR f1.ConvertedDateTime2 IS NULL OR f1.ConvertedDateTimeOffset IS NULL OR
	f2.ConvertedDate IS NULL OR f2.ConvertedDateTime IS NULL OR f2.ConvertedDateTime2 IS NULL OR f2.ConvertedDateTimeOffset IS NULL OR
	f3.ConvertedDate IS NULL OR f3.ConvertedDateTime IS NULL OR f3.ConvertedDateTime2 IS NULL OR f3.ConvertedDateTimeOffset IS NULL OR
	
	CAST(nt.NativeDTtoDTO AS DATE) <> c1.ConvertedDate OR CAST(nt.NativeDTtoDTO AS DATE) <> f1.ConvertedDate OR
	CAST(nt.NativeDTtoDTO AS DATETIME) <> c1.ConvertedDateTime OR CAST(nt.NativeDTtoDTO AS DATETIME) <> f1.ConvertedDateTime OR
	CAST(nt.NativeDTtoDTO AS DATETIME2) <> c1.ConvertedDateTime2 OR CAST(nt.NativeDTtoDTO AS DATETIME2) <> f1.ConvertedDateTime2 OR
	nt.NativeDTtoDTO <> c1.ConvertedDateTimeOffset OR nt.NativeDTtoDTO <> f1.ConvertedDateTimeOffset OR
	
	CAST(nt.NativeDT2toDTO AS DATE) <> c2.ConvertedDate OR CAST(nt.NativeDT2toDTO AS DATE) <> f2.ConvertedDate OR
	CAST(nt.NativeDT2toDTO AS DATETIME) <> c2.ConvertedDateTime OR CAST(nt.NativeDT2toDTO AS DATETIME) <> f2.ConvertedDateTime OR
	CAST(nt.NativeDT2toDTO AS DATETIME2) <> c2.ConvertedDateTime2 OR CAST(nt.NativeDT2toDTO AS DATETIME2) <> f2.ConvertedDateTime2 OR
	nt.NativeDT2toDTO <> c2.ConvertedDateTimeOffset OR nt.NativeDT2toDTO <> f2.ConvertedDateTimeOffset OR
	
	CAST(nt.NativeDTO AS DATE) <> c3.ConvertedDate OR CAST(nt.NativeDTO AS DATE) <> f3.ConvertedDate OR
	CAST(nt.NativeDTO AS DATETIME) <> c3.ConvertedDateTime OR CAST(nt.NativeDTO AS DATETIME) <> f3.ConvertedDateTime OR
	CAST(nt.NativeDTO AS DATETIME2) <> c3.ConvertedDateTime2 OR CAST(nt.NativeDTO AS DATETIME2) <> f3.ConvertedDateTime2 OR
	nt.NativeDTO <> c3.ConvertedDateTimeOffset OR nt.NativeDTO <> f3.ConvertedDateTimeOffset;

	--RETURN;

	SELECT
		h.SourceTimeZoneName,
		h.TargetTimeZoneName,
		s.InputDateTime,
		s.InputDateTime AT TIME ZONE SourceTimeZoneName AT TIME ZONE TargetTimeZoneName NativeDTO
	FROM TimeZoneConversionHelper_CCI h
	CROSS APPLY (
	VALUES
		(-7200),
		(-5400),
		(-3600),
		(-1800),
		(-60),
		(-1),
		(0),
		(1),
		(60),
		(1800),
		(3600),
		(5400),
		(7200),
		(CEILING(0.5 * DATEDIFF_BIG(SECOND, h.IntervalStart, h.IntervalEnd)))
	) second_offsets (offset)
	CROSS APPLY (
		SELECT DATEADD(SECOND, second_offsets.offset, h.IntervalStart)
	) s (InputDateTime)
	CROSS APPLY (
		SELECT s.InputDateTime AT TIME ZONE SourceTimeZoneName AT TIME ZONE TargetTimeZoneName
	) nt (NativeDT2toDTO)
	CROSS APPLY dbo.TZConvertDT2(s.InputDateTime, h.SourceTimeZoneName, h.TargetTimeZoneName) c2
	OUTER APPLY dbo.TZGetOffsetsDT2(s.InputDateTime, h.SourceTimeZoneName, h.TargetTimeZoneName) o
	CROSS APPLY dbo.TZFormatDT2(s.InputDateTime, h.SourceTimeZoneName, h.TargetTimeZoneName, o.OffsetMinutes, o.TargetOffsetMinutes) f2 
	WHERE	
	c2.ConvertedDate IS NULL OR c2.ConvertedDateTime IS NULL OR c2.ConvertedDateTime2 IS NULL OR c2.ConvertedDateTimeOffset IS NULL OR

	f2.ConvertedDate IS NULL OR f2.ConvertedDateTime IS NULL OR f2.ConvertedDateTime2 IS NULL OR f2.ConvertedDateTimeOffset IS NULL OR

	CAST(nt.NativeDT2toDTO AS DATE) <> c2.ConvertedDate OR CAST(nt.NativeDT2toDTO AS DATE) <> f2.ConvertedDate OR
	CAST(nt.NativeDT2toDTO AS DATETIME) <> c2.ConvertedDateTime OR CAST(nt.NativeDT2toDTO AS DATETIME) <> f2.ConvertedDateTime OR
	CAST(nt.NativeDT2toDTO AS DATETIME2) <> c2.ConvertedDateTime2 OR CAST(nt.NativeDT2toDTO AS DATETIME2) <> f2.ConvertedDateTime2 OR
	nt.NativeDT2toDTO <> c2.ConvertedDateTimeOffset OR nt.NativeDT2toDTO <> f2.ConvertedDateTimeOffset
	--OPTION (USE HINT('ENABLE_PARALLEL_PLAN_PREFERENCE')); -- this helps

END;

GO

EXEC #ValidateRefreshTimeZoneConversionHelperTable;
