# Introduction

Microsoft introduced the [`AT TIME ZONE`](https://learn.microsoft.com/en-us/sql/t-sql/queries/at-time-zone-transact-sql?view=sql-server-ver16) operator with the SQL Server 2016 release. That operator may be a performance bottleneck for queries which need to perform many time zone calculations. This repository contains table-valued functions that serve as a replacement for `AT TIME ZONE`. The replacement functions perform 3-10X better than `AT TIME ZONE` under typical conditions.

# Requirements

The code works on SQL Server 2016 SP1 and later, SQL Server 2017 and later, and Azure SQL Database. It likely works on Azure SQL Managed Instance as well but this has not been tested.

The `RefreshTimeZoneConversionHelperTable` stored procedure must be scheduled to execute on a recurring basis.

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

Executing the code from the latest release allows steps 1 - 4 to be skipped.

1. Create the `TimeZoneNames` table type from the other folder.
2. Create the `TimeZoneConversionHelper` table from the tables folder.
3. Create the `RefreshTimeZoneConversionHelperTable` stored procedure from the procedures folder.
4. Create all nine functions from the functions folder.
    - Some environments benefit from customization of the functions. See step 8 for instructions.
5. By default, the `RefreshTimeZoneConversionHelperTable` stored procedure will populate data for all time zones for the past 30 years. Note that the functions are designed to return accurate results even for inputs that aren't mapped in the `TimeZoneConversionHelper` table. Adjust the time period and time zones for the mapping if desired by passing explicit values for the input parameters.
6. Execute the `RefreshTimeZoneConversionHelperTable` stored procedure to populate the `TimeZoneConversionHelper` table.
7. Schedule the `RefreshTimeZoneConversionHelperTable` stored procedure to run on a recurring basis. It is recommended to run the stored procedure daily a few hours after your typical time for applying Windows updates.
8. The functions support a variety of different inputs and scenarios. Consider customizing the functions to better meet your specific needs. For example:
   - You only need functions that support the data types that you use to store your data. For example, if you don't store any data in the `DATETIMEOFFSET` data type then you don't need the three functions that support that data type as an input.
   - If all of your data is stored in the same time zone then you may want create wrapper functinos that hard code a value for the @SourceTimeZoneName parameters.
   - Don't create the simple version of the functions if you want developers to always use the better performing function pairs.


# Remarks

- 24 hour assumption
- aims to reduce the AT TIME ZONE CPU penalty only
- query plan complexity
- mapping misses
- how to reduce the size of the table/procedure runtime
- AT TIME ZONE bugs
