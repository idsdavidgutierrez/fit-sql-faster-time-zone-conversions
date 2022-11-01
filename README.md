# fit-sql-faster-time-zone-conversions



# Requirements




# Functions


# Examples

```TSQL
DECLARE @t TABLE (
	InputDateTime DATETIME,
	InputDateTime2 DATETIME2(7),
	InputDateTimeOffset DATETIMEOFFSET,
	SourceTimeZone SYSNAME,
	TargetTimeZone SYSNAME
);

INSERT INTO @t (InputDateTime, InputDateTime2, InputDateTimeOffset, SourceTimeZone, TargetTimeZone)
VALUES (GETDATE(), SYSDATETIME(), SYSDATETIMEOFFSET(), N'Romance Standard Time', N'Aleutian Standard Time');


-- convert a DATETIME to a DATETIMEOFFSET with fixed source and target time zones using the simple function
SELECT
	t.InputDateTime AT TIME ZONE N'Central Standard Time' AT TIME ZONE N'E. Africa Standard Time',
	c.ConvertedDateTimeOffset
FROM @t t
CROSS APPLY dbo.TZConvertDT(t.InputDateTime, N'Central Standard Time', N'E. Africa Standard Time') c;


-- convert a DATETIMEOFFSET to a DATETIME2 with a dynamic target time zone using the pair of functions
SELECT
	CAST(t.InputDateTimeOffset AT TIME ZONE t.TargetTimeZone AS DATETIME2),
	f.ConvertedDateTime2
FROM @t t
OUTER APPLY dbo.TZGetOffsetsDTO(t.InputDateTimeOffset, t.TargetTimeZone) o
CROSS APPLY dbo.TZFormatDTO(t.InputDateTimeOffset, t.TargetTimeZone, o.OffsetMinutes, o.TargetOffsetMinutes) f;
```

# Setup



# Remarks
