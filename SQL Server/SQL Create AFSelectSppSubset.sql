/*===========================================================================*\
  DataSelector is a MapBasic tool and associated SQL scripts to extract
  biodiversity information from SQL Server based on any selection criteria.
  
  Copyright � 2015 Andy Foy Consulting
  
  This file is part of the MapInfo tool 'DataSelector'.
  
  DataSelector is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.
  
  DataSelector is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with DataSelector.  If not, see <http://www.gnu.org/licenses/>.
\*===========================================================================*/

USE [NBNData_TVERC]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*===========================================================================*\
  Description:	Select species records based on the SQL where clause
                passed by the calling routine.

  Parameters:
	@Schema			The schema for the partner and species table.
	@SpeciesTable	The name of the table contain the species records.
	@WhereClause	The SQL where clause to use during the selection.
	@GroupByClause	The SQL group by clause to use during the selection.
	@OrderByClause	The SQL order by clause to use during the selection.
	@UserId			The userid of the user executing the selection.

  Created:			Andy Foy - Jun 2015
  Last revised:		Andy Foy - Sep 2015

 *****************  Version 3  *****************
 Author: Andy Foy		Date: 09/09/2015
 A. Include group by and order by parameters.
 B. Enable subsets to be non-spatial (i.e. have
	no geometry column.
 C. Remove MapCatalog entry if subset table is
	non-spatial.
 D. Lookup table column names and spatial variables
	from Spatial_Tables.

 *****************  Version 2  *****************
 Author: Andy Foy		Date: 08/06/2015
 A. Include userid as parameter to use in temporary SQL
	table name to enable concurrent use of tool.

 *****************  Version 1  *****************
 Author: Andy Foy		Date: 03/06/2015
 A. Initial version of code based on Data Extractor tool.

\*===========================================================================*/

-- Drop the procedure if it already exists
if exists (select ROUTINE_NAME from INFORMATION_SCHEMA.ROUTINES where ROUTINE_SCHEMA = 'dbo' and ROUTINE_NAME = 'AFSelectSppSubset')
	DROP PROCEDURE dbo.AFSelectSppSubset
GO

-- Create the stored procedure
CREATE PROCEDURE [dbo].[AFSelectSppSubset] @Schema varchar(50),
	@SpeciesTable varchar(50),
	@ColumnNames varchar(1000),
	@WhereClause varchar(1000),
	@GroupByClause varchar(1000),
	@OrderByClause varchar(1000),
	@UserId varchar(50)
AS
BEGIN

	SET NOCOUNT ON

	IF @UserId IS NULL
		SET @UserId = 'temp'

	DECLARE @debug int
	Set @debug = 0

	If @debug = 1
		PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Started.'

	DECLARE @sqlCommand nvarchar(2000)
	DECLARE @params nvarchar(2000)

	DECLARE @TempTable varchar(50)
	SET @TempTable = @SpeciesTable + '_' + @UserId

	-- Drop the index on the sequential primary key of the temporary table if it already exists
	If exists (select column_name from INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE where TABLE_SCHEMA = @Schema and TABLE_NAME = @TempTable and COLUMN_NAME = 'MI_PRINX' and CONSTRAINT_NAME = 'PK_' + @TempTable + '_MI_PRINX')
	BEGIN
		SET @sqlcommand = 'ALTER TABLE ' + @Schema + '.' + @TempTable +
			' DROP CONSTRAINT PK_MI_PRINX'
		EXEC (@sqlcommand)
	END
	
	-- Drop the temporary table if it already exists
	If exists (select TABLE_NAME from INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA = @Schema and TABLE_NAME = @TempTable)
	BEGIN
		If @debug = 1
			PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Dropping temporary table ...'
		SET @sqlcommand = 'DROP TABLE ' + @Schema + '.' + @TempTable
		EXEC (@sqlcommand)
	END

	-- Lookup table column names and spatial variables from Spatial_Tables
	DECLARE @IsSpatial bit
	DECLARE @XColumn varchar(32), @YColumn varchar(32), @SizeColumn varchar(32), @SpatialColumn varchar(32)
	DECLARE @CoordSystem varchar(254)
	
	If @debug = 1
		PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Retrieving table spatial details ...'

	DECLARE @SpatialTable varchar(100)
	SET @SpatialTable ='Spatial_Tables'

	-- Retrieve the table column names and spatial variables
	SET @sqlcommand = 'SELECT @O1 = XColumn, ' +
							 '@O2 = YColumn, ' +
							 '@O3 = SizeColumn, ' +
							 '@O4 = IsSpatial, ' +
							 '@O5 = SpatialColumn, ' +
							 '@O6 = CoordSystem ' +
						'FROM ' + @Schema + '.' + @SpatialTable + ' ' +
						'WHERE TableName = ''' + @SpeciesTable + ''' AND OwnerName = ''' + @Schema + ''''

	SET @params =	'@O1 varchar(32) OUTPUT, ' +
					'@O2 varchar(32) OUTPUT, ' +
					'@O3 varchar(32) OUTPUT, ' +
					'@O4 bit OUTPUT, ' +
					'@O5 varchar(32) OUTPUT, ' +
					'@O6 varchar(254) OUTPUT'
		
	EXEC sp_executesql @sqlcommand, @params,
		@O1 = @XColumn OUTPUT, @O2 = @YColumn OUTPUT, @O3 = @SizeColumn OUTPUT, @O4 = @IsSpatial OUTPUT, 
		@O5 = @SpatialColumn OUTPUT, @O6 = @CoordSystem OUTPUT
		
	If @ColumnNames = ''
		SET @ColumnNames = '*'

	If @IsSpatial = 1
	BEGIN
		IF @debug = 1
			PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Table is spatial'

		If @WhereClause = ''
			SET @WhereClause = 'Spp.SP_GEOMETRY IS NOT NULL'
		Else
			SET @WhereClause = @WhereClause + ' AND Spp.SP_GEOMETRY IS NOT NULL'
	END

	If @GroupByClause <> ''
		SET @GroupByClause = ' GROUP BY ' + @GroupByClause

	If @OrderByClause <> ''
		SET @OrderByClause = ' ORDER BY ' + @OrderByClause

	If @debug = 1
		PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Performing selection ...'

	-- Select the species records into the temporary table
	SET @sqlcommand = 
		'SELECT ' + @ColumnNames +
		' INTO ' + @Schema + '.' + @TempTable +
		' FROM ' + @Schema + '.' + @SpeciesTable + ' As Spp' +
		' WHERE ' + @WhereClause +
		@GroupByClause +
		@OrderByClause
	EXEC (@sqlcommand)

	DECLARE @RecCnt Int
	Set @RecCnt = @@ROWCOUNT

	If @debug = 1
		PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + Cast(@RecCnt As varchar) + ' records selected ...'

	-- If the MapInfo MapCatalog exists then update it
	IF EXISTS (SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'MAPINFO' AND TABLE_NAME = 'MAPINFO_MAPCATALOG')
	BEGIN

		-- Delete the MapInfo MapCatalog entry if it already exists
		IF EXISTS (SELECT TABLENAME FROM [MAPINFO].[MAPINFO_MAPCATALOG] WHERE TABLENAME = @TempTable)
		BEGIN
			IF @debug = 1
				PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Deleting the MapInfo MapCatalog entry ...'
			
			SET @sqlcommand = 'DELETE FROM [MAPINFO].[MAPINFO_MAPCATALOG]' +
				' WHERE TABLENAME = ''' + @TempTable + ''''
			EXEC (@sqlcommand)
		END

		-- Calculate the geometric extent of the records (plus their precision)
		DECLARE @X1 int, @X2 int, @Y1 int, @Y2 int

		SET @X1 = 0
		SET @X2 = 0
		SET @Y1 = 0
		SET @Y2 = 0

		-- Check if the table is spatial and the necessary columns are in the table (including a geometry column)
		IF  @IsSpatial = 1
		AND EXISTS(SELECT * FROM sys.columns WHERE Name = @XColumn AND Object_ID = Object_ID(@TempTable))
		AND EXISTS(SELECT * FROM sys.columns WHERE Name = @YColumn AND Object_ID = Object_ID(@TempTable))
		AND EXISTS(SELECT * FROM sys.columns WHERE Name = @SizeColumn AND Object_ID = Object_ID(@TempTable))
		AND EXISTS(SELECT * FROM sys.columns WHERE Name = @SpatialColumn AND Object_ID = Object_ID(@TempTable))
		AND EXISTS(SELECT * FROM sys.columns WHERE user_type_id = 129 AND Object_ID = Object_ID(@TempTable))
		BEGIN

			IF @debug = 1
				PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Determining spatial extent ...'

			-- Retrieve the geometric extent values and store as variables
			SET @sqlcommand = 'SELECT @xMin = MIN(' + @XColumn + '), ' +
									 '@yMin = MIN(' + @YColumn + '), ' +
									 '@xMax = MAX(' + @XColumn + ') + MAX(' + @SizeColumn + '), ' +
									 '@yMax = MAX(' + @YColumn + ') + MAX(' + @SizeColumn + ') ' +
									 'FROM ' + @Schema + '.' + @TempTable

			SET @params =	'@xMin int OUTPUT, ' +
							'@yMin int OUTPUT, ' +
							'@xMax int OUTPUT, ' +
							'@yMax int OUTPUT'
		
			EXEC sp_executesql @sqlcommand, @params,
				@xMin = @X1 OUTPUT, @yMin = @Y1 OUTPUT, @xMax = @X2 OUTPUT, @yMax = @Y2 OUTPUT
		
			If @debug = 1
				PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Inserting the MapInfo MapCatalog entry ...'

			---- Check if the spatial column is in the table
			--IF NOT EXISTS(SELECT * FROM sys.columns WHERE Name = N'SP_GEOMETRY' AND Object_ID = Object_ID(@TempTable))
			--BEGIN
			--	SET @sqlcommand = 'ALTER TABLE ' + @TempTable + ' ADD SP_GEOMETRY Geometry NULL'
			--	EXEC (@sqlcommand)
			--END

			-- Check if the rendition column is in the table
			IF NOT EXISTS(SELECT * FROM sys.columns WHERE Name = N'MI_STYLE' AND Object_ID = Object_ID(@TempTable))
			BEGIN
				SET @sqlcommand = 'ALTER TABLE ' + @TempTable + ' ADD MI_STYLE varchar(254) NULL'
				EXEC (@sqlcommand)
			END
			
			-- Adding table to MapInfo MapCatalog
			INSERT INTO [MAPINFO].[MAPINFO_MAPCATALOG]
				([SPATIALTYPE]
				,[TABLENAME]
				,[OWNERNAME]
				,[SPATIALCOLUMN]
				,[DB_X_LL]
				,[DB_Y_LL]
				,[DB_X_UR]
				,[DB_Y_UR]
				,[COORDINATESYSTEM]
				,[SYMBOL]
				,[XCOLUMNNAME]
				,[YCOLUMNNAME]
				,[RENDITIONTYPE]
				,[RENDITIONCOLUMN]
				,[RENDITIONTABLE]
				,[NUMBER_ROWS])
--				,[VIEW_X_LL]
--				,[VIEW_Y_LL]
--				,[VIEW_X_UR]
--				,[VIEW_Y_UR])
			VALUES
				(17.3
				,@TempTable
				,@Schema
				,@SpatialColumn
				,@X1
				,@Y1
				,@X2
				,@Y2
				,@CoordSystem
				,'Pen (1,2,0)  Brush (1,16777215,16777215)'
				,NULL
				,NULL
				,NULL
				,'MI_STYLE'
				,NULL
				,@RecCnt)
--				,NULL
--				,NULL
--				,NULL
--				,NULL)
		END

	END
	ELSE
	-- If the MapInfo MapCatalog doesn't exist then skip updating it
	BEGIN
		If @debug = 1
			PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'MapInfo MapCatalog not found - skipping update ...'
	END

	If @debug = 1
		PRINT CONVERT(VARCHAR(32), CURRENT_TIMESTAMP, 109 ) + ' : ' + 'Ended.'

END
GO