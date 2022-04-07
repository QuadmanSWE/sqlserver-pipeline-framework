WITH reftree
AS
(
		SELECT
			ObjectId			= ReferencingTables.object_id ,
			SchemaName			= OBJECT_SCHEMA_NAME(ReferencingTables.object_id) ,
			TableName			= ReferencingTables.name ,
			Depth				= 1
			--,CAST(ReferencingTables.object_id as varchar(4000))  AS Chain
		FROM
			sys.tables AS ReferencingTables
		LEFT OUTER JOIN
			sys.foreign_keys AS ForeignKeys
		ON
			ReferencingTables.object_id = ForeignKeys.parent_object_id
		AND
			ReferencingTables.object_id != ForeignKeys.referenced_object_id
		WHERE
			ForeignKeys.object_id IS NULL
		AND
			ReferencingTables.is_ms_shipped = 0
		-- Only get tables with a primary key
		AND EXISTS (
			SELECT NULL
			FROM sys.indexes AS ind
			WHERE
				ind.object_id = ReferencingTables.object_id
			AND ind.is_primary_key = 1
		)
		AND EXISTS (SELECT * FROM sys.partitions as p WHERE p.rows > 0 AND p.object_id = ReferencingTables.object_id)
			
		UNION ALL
		
		SELECT
			ObjectId			= ReferencingTables.object_id ,
			SchemaName			= OBJECT_SCHEMA_NAME(ReferencingTables.object_id) ,
			TableName			= ReferencingTables.name ,
			Depth				= TableHierarchy.Depth + 1
			--,CAST(TableHierarchy.Chain + '-' + CAST(ReferencingTables.object_id as varchar(4000)) AS VARCHAR(4000)) AS Chain

		FROM
			sys.tables AS ReferencingTables
		INNER JOIN
			sys.foreign_keys AS ForeignKeys
		ON
			ReferencingTables.object_id = ForeignKeys.parent_object_id
		AND
			ReferencingTables.object_id != ForeignKeys.referenced_object_id
		INNER JOIN
			reftree AS TableHierarchy
		ON
			ForeignKeys.referenced_object_id = TableHierarchy.ObjectId
		WHERE 
		-- Only get tables with a primary key
		EXISTS (
			SELECT NULL
			FROM sys.indexes AS ind
			WHERE
				ind.object_id = ReferencingTables.object_id
			AND ind.is_primary_key = 1
			)
		AND EXISTS (SELECT * FROM sys.partitions as p WHERE p.rows > 0 AND p.object_id = ReferencingTables.object_id)
)
SELECT
	SchemaName,TableName
FROM reftree
WHERE TableName <> 'SchemaVersions' --never include this
GROUP BY SchemaName,TableName
ORDER BY
	MAX(Depth) asc
;