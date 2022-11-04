SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE TABLE [dbo].[TimeZoneConversionHelper_RS](
	[SourceTimeZoneNameChecksum] INT NOT NULL,
	[TargetTimeZoneNameChecksum] INT NOT NULL,
	[IntervalStart] [datetime2](7) NOT NULL,
	[IntervalEnd] [datetime2](7) NOT NULL,
	[OffsetMinutes] [int] NOT NULL,
	[TargetOffsetMinutes] [int] NOT NULL,
	CONSTRAINT PK_TimeZoneConversionHelper_RS PRIMARY KEY ([SourceTimeZoneNameChecksum], [TargetTimeZoneNameChecksum], [IntervalStart])
);
