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
   - If all of your data is stored in the same time zone then you may want create wrapper functinos that hard code a value for the `@SourceTimeZoneName` parameters.
   - Don't create the simple version of the functions if you want developers to always use the better performing function pairs.

# Remarks

- The `RefreshTimeZoneConversionHelperTable` stored procedure uses a sampling technique that assumes that a time zone won't change its offset back and forth to the same value within any 24 hour period. As of October 2022, the shortest historical switch is 28 days for the Fiji Standard Time. If you feel that 24 hours is too generous of an assumption it is possible to change the value of the `@SampleHours` variable in `RefreshTimeZoneConversionHelperTable`.
- The provided functions aim to reduce the CPU time required to perform time zone calculations only. If a query performance problem is caused by a poor cardinality estimate instead of a large number of `AT TIME ZONE` executions then changing to use these functions may not resolve the issue.
- Replacing `AT TIME ZONE` with these functions is equivalent to adding a join to the query for each function call. This will increase query plan complexity and in some cases may degrade performance for very complex queries.
- The functions work by looking for a match in the `TimeZoneConversionHelper` table. If no match is found then fallback code runs which calls the `AT TIME ZONE` operator. Query performance will improve as the percentage of matched inputs increases but the correct results should be returned even if there is no matching row in the table.
- The `TimeZoneConversionHelper` table takes up around 350 MB of space with default parameters for `RefreshTimeZoneConversionHelperTable`. The best way to reduce the size of the table is to call `RefreshTimeZoneConversionHelperTable` with the `@TimeZoneFilter` parameter set to the time zones relevant to your environment.
- The functions aim to mimic the behavior of the `AT TIME ZONE` operator. `AT TIME ZONE` uses a Windows mechanism which does not have all historical rule changes. The functions will also not reflect all historical rule changes, mostly prior to 2003.
