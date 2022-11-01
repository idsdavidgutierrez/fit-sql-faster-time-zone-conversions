# Introduction



# Requirements

2016 SP1+, azure, MI?

Scheduled process to run the procedure


# Functions

need sub headers for different types


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

( release skips steps 1- 4)

1. Creae table type
2. Create table
3. Create stored procedure
4. Create functions
5. Pick parameters for stored procedure
6. Run the stored procedure
7. Schedule the stored procedure to run daily
8. Consider customizing the functions
9. Validate functions



# Remarks

- 24 hour assumption
- aims to reduce the AT TIME ZONE CPU penalty only
- query plan complexity
- mapping misses
- how to reduce the size of the table/procedure runtime
- AT TIME ZONE bugs
