-- This is currently the complete, authoritative schema, as it is easier to
-- understand all in one place and unnecessary to use proper evolutions until
-- production.  Play only checks for changes in the most recent evolution, so
-- changing this file will not prompt an evolution while 2.sql is unchanged.

-- Theoretically this could be maintained as authoritative during production,
-- with further evolutions only making defensive changes, but it may be easier
-- to keep separate.

-- A general convention is that hard-coded fixtures get non-positive ids.

-- Currently these are largely under-indexed.

# --- !Ups
;

----------------------------------------------------------- utilities

-- Note that the double-semicolons are necessary for play's poor evolution parsing
CREATE FUNCTION create_abstract_parent ("parent" name, "children" name[]) RETURNS void LANGUAGE plpgsql AS $create$
DECLARE
	parent_table CONSTANT text := quote_ident(parent);;
	kind_type CONSTANT text := quote_ident(parent || '_kind');;
BEGIN
	EXECUTE $macro$
		CREATE TYPE $macro$ || kind_type || $macro$ AS ENUM ('$macro$ || array_to_string(children, $$','$$) || $macro$');;
		CREATE TABLE $macro$ || parent_table || $macro$ (
			"id" serial NOT NULL Primary Key,
			"kind" $macro$ || kind_type || $macro$ NOT NULL
		);;
		CREATE FUNCTION $macro$ || quote_ident(parent || '_trigger') || $macro$ () RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
			IF TG_OP = 'INSERT' THEN
				INSERT INTO $macro$ || parent_table || $macro$ (id, kind) VALUES (NEW.id, TG_TABLE_NAME::$macro$ || kind_type || $macro$);;
			ELSIF TG_OP = 'DELETE' THEN
				DELETE FROM $macro$ || parent_table || $macro$ WHERE id = OLD.id AND kind = TG_TABLE_NAME::$macro$ || kind_type || $macro$;;
			ELSIF TG_OP = 'UPDATE' THEN
				IF NEW.id = OLD.id THEN
					RETURN NEW;;
				END IF;;
				UPDATE $macro$ || parent_table || $macro$ SET id = NEW.id WHERE id = OLD.id AND kind = TG_TABLE_NAME::$macro$ || kind_type || $macro$;;
			END IF;;
			IF NOT FOUND THEN
				RAISE EXCEPTION 'inconsistency for %:% parent $macro$ || parent || $macro$', TG_TABLE_NAME::$macro$ || kind_type || $macro$, OLD.id;;
			END IF;;
			IF TG_OP = 'DELETE' THEN
				RETURN OLD;;
			ELSE
				RETURN NEW;;
			END IF;;
		END;;$$
	$macro$;;
END;; $create$;
COMMENT ON FUNCTION "create_abstract_parent" (name, name[]) IS 'A "macro" to create an abstract parent table and trigger function.  This could be done with a single function using dynamic EXECUTE but this way is more efficient and not much more messy.';

CREATE FUNCTION cast_int ("input" text) RETURNS integer LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
	i integer;;
BEGIN
	SELECT input::integer INTO i;;
	RETURN i;;
EXCEPTION WHEN invalid_text_representation THEN
	RETURN NULL;;
END;; $$;

CREATE FUNCTION singleton (int4) RETURNS int4range LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT int4range($1, $1, '[]') $$;

----------------------------------------------------------- auditing

CREATE TYPE audit_action AS ENUM ('login', 'logout', 'add', 'change', 'remove', 'download');
COMMENT ON TYPE audit_action IS 'The various activities for which we keep audit records (in audit or a derived table).';

CREATE TABLE "audit" (
	"when" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	"who" int NOT NULL, -- References "account" ("party"),
	"ip" inet NOT NULL,
	"action" audit_action NOT NULL
) WITH (OIDS = FALSE);
COMMENT ON TABLE "audit" IS 'Logs of all activities on the site, including access and modifications to any data. Each table has an associated audit table inheriting from this one.';

----------------------------------------------------------- users

CREATE TABLE "party" (
	"id" serial NOT NULL Primary Key,
	"name" text NOT NULL,
	"orcid" char(16)
);
COMMENT ON TABLE "party" IS 'Users, groups, organizations, and other logical identities';

-- special party (SERIAL starts at 1):
INSERT INTO "party" VALUES (-1, 'Everybody'); -- NOBODY
INSERT INTO "party" VALUES (0, 'Databrary'); -- ROOT

CREATE TABLE "audit_party" (
	LIKE "party"
) INHERITS ("audit") WITH (OIDS = FALSE);


CREATE TABLE "account" (
	"id" integer NOT NULL Primary Key References "party",
	"email" varchar(256) NOT NULL, -- split out (multiple/user)?
	"password" varchar(60), -- standard unix-style hash, currently $2a$ bcrypt
	"openid" varchar(256) -- split out (multiple/user)?
);
COMMENT ON TABLE "account" IS 'Login information for parties associated with registered individuals.';

CREATE TABLE "audit_account" (
	LIKE "account"
) INHERITS ("audit") WITH (OIDS = FALSE);

----------------------------------------------------------- permissions

CREATE TYPE permission AS ENUM ('NONE',
	'VIEW', -- list view, but no access to protected data (PUBLIC access)
	'DOWNLOAD', -- full read access to shared data (BROWSE access)
	'CONTRIBUTE', -- create and edit data of own/target (FULL access)
	'ADMIN' -- perform administrative tasks on site/target such as changing permissions
);
COMMENT ON TYPE permission IS 'Levels of access parties can have to the site data.';

CREATE TYPE consent AS ENUM (
	-- 		permission required
	'PRIVATE', 	-- CONTRIBUTE	did not consent to any sharing
	'SHARED', 	-- DOWNLOAD	consented to share on databrary
	'EXCERPTS', 	-- DOWNLOAD	SHARED, but consented that excerpts may be PUBLIC
	'PUBLIC' 	-- VIEW		consented to share openly
);
COMMENT ON TYPE consent IS 'Levels of sharing that participants may consent to.';

CREATE TABLE "authorize" (
	"child" integer NOT NULL References "party" ON DELETE Cascade,
	"parent" integer NOT NULL References "party",
	"access" permission NOT NULL DEFAULT 'NONE',
	"delegate" permission NOT NULL DEFAULT 'NONE',
	"authorized" timestamp DEFAULT CURRENT_TIMESTAMP,
	"expires" timestamp,
	Primary Key ("parent", "child"),
	Check ("child" <> "parent" AND ("child" > 0 OR "parent" = -1))
);
COMMENT ON TABLE "authorize" IS 'Relationships and permissions granted between parties';
COMMENT ON COLUMN "authorize"."child" IS 'Party granted permissions';
COMMENT ON COLUMN "authorize"."parent" IS 'Party granting permissions';
COMMENT ON COLUMN "authorize"."access" IS 'Level of independent site access granted to child (effectively minimum level on path to ROOT)';
COMMENT ON COLUMN "authorize"."delegate" IS 'Permissions for which child may act as parent (not inherited)';

CREATE TABLE "audit_authorize" (
	LIKE "authorize"
) INHERITS ("audit") WITH (OIDS = FALSE);

-- To allow normal users to inherit from nobody:
INSERT INTO "authorize" ("child", "parent", "access", "delegate") VALUES (0, -1, 'ADMIN', 'ADMIN');

CREATE VIEW "authorize_valid" AS
	SELECT * FROM authorize WHERE authorized < CURRENT_TIMESTAMP AND (expires IS NULL OR expires > CURRENT_TIMESTAMP);
COMMENT ON VIEW "authorize_valid" IS 'Active records from "authorize"';

CREATE FUNCTION "authorize_access_parents" (IN "child" integer, OUT "parent" integer, INOUT "access" permission = NULL) RETURNS SETOF RECORD LANGUAGE sql STABLE AS $$
	WITH RECURSIVE closure AS (
		SELECT $1 AS parent, enum_last(null::permission) AS access
		UNION
		SELECT p.parent, LEAST(p.access, c.access)
			FROM authorize_valid p, closure c
			WHERE p.child = c.parent AND ($2 IS NULL OR p.access >= $2)
	)
	SELECT * FROM closure
$$;
COMMENT ON FUNCTION "authorize_access_parents" (integer, permission) IS 'All ancestors (recursive) of a given child';

CREATE FUNCTION "authorize_access_check" ("child" integer, "parent" integer = 0, "access" permission = NULL) RETURNS permission LANGUAGE sql STABLE AS $$
	SELECT max(access) FROM authorize_access_parents($1, $3) WHERE parent = $2
$$;
COMMENT ON FUNCTION "authorize_access_check" (integer, integer, permission) IS 'Test if a given child inherits the given permission [any] from the given parent [root]';

CREATE FUNCTION "authorize_delegate_check" ("child" integer, "parent" integer, "delegate" permission = NULL) RETURNS permission LANGUAGE sql STABLE AS $$
	SELECT CASE WHEN $1 = $2 THEN enum_last(max(delegate)) ELSE max(delegate) END FROM authorize_valid WHERE child = $1 AND parent = $2
$$;
COMMENT ON FUNCTION "authorize_delegate_check" (integer, integer, permission) IS 'Test if a given child has the given permission [any] over the given parent';

----------------------------------------------------------- volumes

CREATE TABLE "volume" (
	"id" serial NOT NULL Primary Key,
	"name" text NOT NULL,
	"body" text
);
COMMENT ON TABLE "volume" IS 'Basic organizational unit for data.';

CREATE TABLE "audit_volume" (
	LIKE "volume"
) INHERITS ("audit") WITH (OIDS = FALSE);
CREATE INDEX "volume_creation_idx" ON audit_volume ("id") WHERE "action" = 'add';
COMMENT ON INDEX "volume_creation_idx" IS 'Allow efficient retrieval of volume creation information, specifically date.';

CREATE TABLE "volume_access" (
	"volume" integer NOT NULL References "volume",
	"party" integer NOT NULL References "party",
	"access" permission NOT NULL DEFAULT 'NONE',
	"inherit" permission NOT NULL DEFAULT 'NONE' Check ("inherit" < 'ADMIN'),
	Check ("access" >= "inherit"),
	Primary Key ("volume", "party")
);
COMMENT ON TABLE "volume_access" IS 'Permissions over volumes assigned to users.';

CREATE TABLE "audit_volume_access" (
	LIKE "volume_access"
) INHERITS ("audit") WITH (OIDS = FALSE);

CREATE FUNCTION "volume_access_check" ("volume" integer, "party" integer, "access" permission = NULL) RETURNS permission LANGUAGE sql STABLE AS $$
	WITH sa AS (
		SELECT party, access, inherit
		  FROM volume_access 
		 WHERE volume = $1 AND ($3 IS NULL OR access >= $3)
	)
	SELECT max(access) FROM (
		SELECT access 
		  FROM sa
		 WHERE party = $2
	UNION ALL
		SELECT LEAST(sa.inherit, aap.access) 
		  FROM sa JOIN authorize_access_parents($2, $3) aap ON party = parent 
	UNION ALL
		SELECT LEAST(sa.access, ad.delegate)
		  FROM sa JOIN authorize_valid ad ON party = parent 
		 WHERE child = $2
	) a WHERE $3 IS NULL OR access >= $3
$$;
COMMENT ON FUNCTION "volume_access_check" (integer, integer, permission) IS 'Test if a given party has the given permission [any] on the given volume, either directly, inherited through site access, or delegated.';

----------------------------------------------------------- time intervals

CREATE FUNCTION "interval_mi_epoch" (interval, interval) RETURNS double precision LANGUAGE sql IMMUTABLE STRICT AS 
	$$ SELECT date_part('epoch', interval_mi($1, $2)) $$;
CREATE TYPE segment AS RANGE (
	SUBTYPE = interval HOUR TO SECOND,
	SUBTYPE_DIFF = "interval_mi_epoch"
);
COMMENT ON TYPE "segment" IS 'Intervals of time, used primarily for representing clips of timeseries data.';

CREATE FUNCTION "segment" (interval) RETURNS segment LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT segment('0', $1) $$;
COMMENT ON FUNCTION "segment" (interval) IS 'The segment [0,X) but strict in X.';
CREATE FUNCTION "duration" (segment) RETURNS interval HOUR TO SECOND LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT CASE WHEN isempty($1) THEN '0' ELSE interval_mi(upper($1), lower($1)) END $$;
COMMENT ON FUNCTION "duration" (segment) IS 'Determine the length of a segment, or NULL if unbounded.';
CREATE FUNCTION "singleton" (interval HOUR TO SECOND) RETURNS segment LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT segment($1, $1, '[]') $$;
CREATE FUNCTION "singleton" (segment) RETURNS interval LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT lower($1) WHERE lower_inc($1) AND upper_inc($1) AND lower($1) = upper($1) $$;
COMMENT ON FUNCTION "singleton" (segment) IS 'Determine if a segment represents a single point and return it, or NULL if not.';

CREATE FUNCTION "segment_shift" (segment, interval) RETURNS segment LANGUAGE sql IMMUTABLE STRICT AS $$
	SELECT CASE WHEN isempty($1) THEN 'empty' ELSE
		segment(lower($1) + $2, upper($1) + $2,
			CASE WHEN lower_inc($1) THEN '[' ELSE '(' END || CASE WHEN upper_inc($1) THEN ']' ELSE ')' END)
	END
$$;
COMMENT ON FUNCTION "segment_shift" (segment, interval) IS 'Shift both end points of a segment by the specified interval.';


CREATE TABLE "object_segment" ( -- ABSTRACT
	"source" integer NOT NULL, -- References "source_table"
	"segment" segment NOT NULL Check (NOT isempty("segment")),
	Check (false) NO INHERIT
);
ALTER TABLE "object_segment" ALTER COLUMN "segment" SET STORAGE plain;
COMMENT ON TABLE "object_segment" IS 'Generic table for objects defined as a temporal sub-sequence of another object.  Inherit from this table to use the functions below.';

CREATE FUNCTION "object_segment_contains" ("object_segment", "object_segment") RETURNS boolean LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT $1.source = $2.source AND $1.segment @> $2.segment $$;
CREATE FUNCTION "object_segment_within" ("object_segment", "object_segment") RETURNS boolean LANGUAGE sql IMMUTABLE STRICT AS
	$$ SELECT $1.source = $2.source AND $1.segment <@ $2.segment $$;
CREATE OPERATOR @> (PROCEDURE = "object_segment_contains", LEFTARG = "object_segment", RIGHTARG = "object_segment", COMMUTATOR = <@);
CREATE OPERATOR <@ (PROCEDURE = "object_segment_within", LEFTARG = "object_segment", RIGHTARG = "object_segment", COMMUTATOR = @>);

----------------------------------------------------------- containers

CREATE TABLE "container" (
	"id" serial NOT NULL Primary Key,
	"volume" integer NOT NULL References "volume",
	"name" text,
	"date" date
);
COMMENT ON TABLE "container" IS 'Organizational unit within volume containing related files (with common annotations), often corresponding to an individual data session (single visit/acquisition/participant/group/day).';
CREATE INDEX ON "container" ("volume");

CREATE TABLE "audit_container" (
	LIKE "container"
) INHERITS ("audit") WITH (OIDS = FALSE);


CREATE TABLE "slot" (
	"id" serial NOT NULL Primary Key,
	"source" integer NOT NULL References "container",
	"segment" segment NOT NULL Default '(,)',
	"consent" consent,
	Unique ("source", "segment"),
	Exclude USING gist (singleton("source") WITH =, "segment" WITH &&) WHERE ("consent" IS NOT NULL)
) INHERITS ("object_segment");
CREATE INDEX "slot_full_container_idx" ON "slot" ("source") WHERE "segment" = '(,)';
COMMENT ON TABLE "slot" IS 'Sections of containers selected for referencing, annotating, consenting, etc.';
COMMENT ON COLUMN "slot"."consent" IS 'Sharing/release permissions granted by participants on (portions of) contained data.  This could equally well be an annotation, but hopefully won''t add too much space here.';

CREATE TABLE "audit_slot" (
	LIKE "slot"
) INHERITS ("audit") WITH (OIDS = FALSE);
COMMENT ON TABLE "audit_slot" IS 'Partial auditing for slot table covering only consent changes.';


CREATE VIEW "slot_nesting" ("child", "parent", "consent") AS 
	SELECT c.id, p.id, p.consent FROM slot c JOIN slot p ON c <@ p;
COMMENT ON VIEW "slot_nesting" IS 'Transitive closure of slots containtained within other slots.';


CREATE FUNCTION "slot_consent" ("slot" integer) RETURNS consent LANGUAGE sql STABLE STRICT AS
	$$ SELECT consent FROM slot_nesting WHERE child = $1 AND consent IS NOT NULL $$;
COMMENT ON FUNCTION "slot_consent" (integer) IS 'Effective consent level on a given slot.';

----------------------------------------------------------- assets

CREATE TYPE classification AS ENUM (
	'IDENTIFIED', 	-- data containing HIPPA identifiers, requiring appropriate consent and DOWNLOAD permission
	'EXCERPT', 	-- IDENTIFIED data that has been selected as a releasable excerpt
	'DEIDENTIFIED', -- "raw" data which has been de-identified, requiring only DOWNLOAD permission
	'ANALYSIS', 	-- un/de-identified derived, generated, summarized, or aggregated data measures
	'PRODUCT',	-- research products such as results, summaries, commentaries, discussions, manuscripts, or articles
	'MATERIAL'	-- materials not derived from data, such as proposals, procedures, stimuli, manuals, (blank) forms, or documentation
);

CREATE TABLE "format" (
	"id" smallserial NOT NULL Primary Key,
	"mimetype" varchar(128) NOT NULL Unique,
	"extension" varchar(8),
	"name" text NOT NULL
);
COMMENT ON TABLE "format" IS 'Possible types for assets, sufficient for producing download headers.';

CREATE TABLE "timeseries_format" (
	Primary Key ("id"),
	Unique ("mimetype")
) INHERITS ("format");
COMMENT ON TABLE "timeseries_format" IS 'Special asset types that correspond to internal formats representing timeseries data.';

-- The privledged formats with special handling (image and video for now) have hard-coded IDs:
INSERT INTO "format" ("id", "mimetype", "extension", "name") VALUES (-700, 'image/jpeg', 'jpg', 'JPEG');
INSERT INTO "timeseries_format" ("id", "mimetype", "extension", "name") VALUES (-800, 'video/mp4', 'mp4', 'Databrary video');

-- The above video format will change to reflect internal storage, these are used for uploaded files:
INSERT INTO "format" ("mimetype", "extension", "name") VALUES ('text/plain', 'txt', 'Plain text');
-- INSERT INTO "format" ("mimetype", "extension", "name") VALUES ('text/html', 'html', 'Hypertext markup');
INSERT INTO "format" ("mimetype", "extension", "name") VALUES ('application/pdf', 'pdf', 'Portable document');
-- INSERT INTO "format" ("mimetype", "extension", "name") VALUES ('video/mp4', 'mp4', 'MPEG-4 Part 14');
-- INSERT INTO "format" ("mimetype", "extension", "name") VALUES ('video/webm', 'webm', 'WebM');

SELECT create_abstract_parent('asset', ARRAY['file', 'timeseries', 'clip']);
COMMENT ON TABLE "asset" IS 'Parent table for all uploaded data in storage.';

CREATE TABLE "file" (
	"id" integer NOT NULL DEFAULT nextval('asset_id_seq') Primary Key References "asset" Deferrable Initially Deferred,
	"format" smallint NOT NULL References "format",
	"classification" classification NOT NULL
);
CREATE TRIGGER "asset" BEFORE INSERT OR UPDATE OR DELETE ON "file" FOR EACH ROW EXECUTE PROCEDURE "asset_trigger" ();
COMMENT ON TABLE "file" IS 'Assets in storage along with their "constant" metadata.';

CREATE TABLE "timeseries" (
	"id" integer NOT NULL DEFAULT nextval('asset_id_seq') Primary Key References "asset" Deferrable Initially Deferred,
	"format" smallint NOT NULL References "timeseries_format",
	"duration" interval HOUR TO SECOND NOT NULL Check ("duration" > interval '0')
) INHERITS ("file");
CREATE TRIGGER "asset" BEFORE INSERT OR UPDATE OR DELETE ON "timeseries" FOR EACH ROW EXECUTE PROCEDURE "asset_trigger" ();
COMMENT ON TABLE "timeseries" IS 'File assets representing interpretable and sub-selectable timeseries data (e.g., videos).';

CREATE TABLE "audit_file" (
	LIKE "file"
) INHERITS ("audit") WITH (OIDS = FALSE);


CREATE TABLE "clip" (
	"id" integer NOT NULL DEFAULT nextval('asset_id_seq') Primary Key References "asset" Deferrable Initially Deferred,
	"source" integer NOT NULL References "timeseries",
	"segment" segment NOT NULL Check (lower("segment") >= '0'::interval AND NOT upper_inf("segment")), -- segment <@ [0,source.duration]
	Unique ("source", "segment")
) INHERITS ("object_segment");
CREATE TRIGGER "asset" BEFORE INSERT OR UPDATE OR DELETE ON "clip" FOR EACH ROW EXECUTE PROCEDURE "asset_trigger" ();
CREATE INDEX ON "clip" ("source");
COMMENT ON TABLE "clip" IS 'Sections of timeseries assets selected for use.  When placed into containers, they are treated independently of their source timeseries.';


CREATE TABLE "container_asset" (
	"asset" integer NOT NULL References "asset" Primary Key,
	"container" integer NOT NULL References "container",
	"offset" interval HOUR TO SECOND,
	"name" text NOT NULL,
	"body" text
);
CREATE INDEX ON "container_asset" ("container");
COMMENT ON TABLE "container_asset" IS 'Asset linkages into containers along with "dynamic" metadata.';
COMMENT ON COLUMN "container_asset"."offset" IS 'Start point or position of this asset within the container, such that this asset occurs or starts offset time after the beginning of the container session.  NULL offsets are treated as universal (existing at all times).';

CREATE TABLE "audit_container_asset" (
	LIKE "container_asset"
) INHERITS ("audit") WITH (OIDS = FALSE);


CREATE VIEW "asset_duration" ("id", "duration") AS
	SELECT id, NULL FROM ONLY file UNION ALL
	SELECT id, duration FROM timeseries UNION ALL
	SELECT id, duration(segment) FROM clip;
COMMENT ON VIEW "asset_duration" IS 'All assets along with their temporal durations, NULL for non-timeseries.';


CREATE TABLE "toplevel_slot" (
	"slot" integer NOT NULL Primary Key References "slot"
);
COMMENT ON TABLE "toplevel_slot" IS 'Slots whose assets are promoted to the top volume level for display.';

CREATE TABLE "audit_toplevel_slot" (
	LIKE "toplevel_slot"
) INHERITS ("audit") WITH (OIDS = FALSE);

CREATE TABLE "toplevel_asset" (
	"slot" integer NOT NULL References "slot",
	"asset" integer NOT NULL References "asset",
	"excerpt" boolean NOT NULL Default false,
	Primary Key ("slot", "asset")
);
COMMENT ON TABLE "toplevel_asset" IS 'Slot assets which are promoted to the top volume level for display.';
COMMENT ON COLUMN "toplevel_asset"."excerpt" IS 'Asset segments that may be released publically if so permitted.';

CREATE TABLE "audit_toplevel_asset" (
	LIKE "toplevel_asset"
) INHERITS ("audit") WITH (OIDS = FALSE);

----------------------------------------------------------- annotations

SELECT create_abstract_parent('annotation', ARRAY['comment','tag','record']);
COMMENT ON TABLE "annotation" IS 'Parent table for metadata annotations.';


CREATE TABLE "comment" (
	"id" integer NOT NULL DEFAULT nextval('annotation_id_seq') Primary Key References "annotation" Deferrable Initially Deferred,
	"who" integer NOT NULL References "account",
	"when" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	"text" text NOT NULL
);
CREATE TRIGGER "annotation" BEFORE INSERT OR UPDATE OR DELETE ON "comment" FOR EACH ROW EXECUTE PROCEDURE "annotation_trigger" ();
COMMENT ON TABLE "comment" IS 'Free-text comments that can be added to nodes (unaudited, immutable).';


CREATE TABLE "record_category" (
	"id" smallserial Primary Key,
	"name" varchar(64) NOT NULL Unique
);
COMMENT ON TABLE "record_category" IS 'Types of records that are relevant for data organization.';
INSERT INTO "record_category" ("id", "name") VALUES (-500, 'participant');

CREATE TABLE "record" (
	"id" integer NOT NULL DEFAULT nextval('annotation_id_seq') Primary Key References "annotation" Deferrable Initially Deferred,
	"volume" integer NOT NULL References "volume",
	"category" smallint References "record_category" ON DELETE SET NULL
);
CREATE TRIGGER "annotation" BEFORE INSERT OR UPDATE OR DELETE ON "record" FOR EACH ROW EXECUTE PROCEDURE "annotation_trigger" ();
COMMENT ON TABLE "record" IS 'Sets of metadata measurements organized into or applying to a single cohesive unit.  These belong to the object(s) they''re attached to, which are expected to be within a single volume.';

CREATE TYPE data_type AS ENUM ('text', 'number', 'date');
COMMENT ON TYPE data_type IS 'Types of measurement data corresponding to measure_* tables.';

CREATE TABLE "metric" (
	"id" serial Primary Key,
	"name" varchar(64) NOT NULL,
	"classification" classification NOT NULL Default 'DEIDENTIFIED',
	"type" data_type NOT NULL,
	"values" text[] -- options for text enumerations, not enforced (could be pulled out to separate kind/table)
);
COMMENT ON TABLE "metric" IS 'Types of measurements for data stored in measure_$type tables.  Rough prototype.';
INSERT INTO "metric" ("id", "name", "type") VALUES (-900, 'ident', 'text');
INSERT INTO "metric" ("id", "name", "classification", "type") VALUES (-590, 'birthdate', 'IDENTIFIED', 'date');
INSERT INTO "metric" ("id", "name", "type", "values") VALUES (-580, 'gender', 'text', ARRAY['F','M']);

CREATE TABLE "record_template" (
	"category" smallint References "record_category" ON DELETE CASCADE,
	"metric" int References "metric",
	Primary Key ("category", "metric")
);
COMMENT ON TABLE "record_template" IS 'Default set of measures defining a given record category.';
INSERT INTO "record_template" ("category", "metric") VALUES (-500, -900);
INSERT INTO "record_template" ("category", "metric") VALUES (-500, -590);
INSERT INTO "record_template" ("category", "metric") VALUES (-500, -580);

CREATE TABLE "measure" ( -- ABSTRACT
	"record" integer NOT NULL References "record" ON DELETE CASCADE,
	"metric" integer NOT NULL References "metric", -- WHERE kind = table_name
	Primary Key ("record", "metric"),
	Check (false) NO INHERIT
);
COMMENT ON TABLE "measure" IS 'Abstract parent of all measure tables containing data values.  Rough prototype.';

CREATE TABLE "measure_text" (
	"record" integer NOT NULL References "record" ON DELETE CASCADE,
	"metric" integer NOT NULL References "metric", -- WHERE kind = "text"
	"datum" text NOT NULL,
	Primary Key ("record", "metric")
) INHERITS ("measure");

CREATE TABLE "measure_number" (
	"record" integer NOT NULL References "record" ON DELETE CASCADE,
	"metric" integer NOT NULL References "metric", -- WHERE kind = "number"
	"datum" numeric NOT NULL,
	Primary Key ("record", "metric")
) INHERITS ("measure");

CREATE TABLE "measure_date" (
	"record" integer NOT NULL References "record" ON DELETE CASCADE,
	"metric" integer NOT NULL References "metric", -- WHERE kind = "date"
	"datum" date NOT NULL,
	Primary Key ("record", "metric")
) INHERITS ("measure");

CREATE VIEW "measure_view" AS
	SELECT record, metric, datum FROM measure_text UNION ALL
	SELECT record, metric, text(datum) FROM measure_number UNION ALL
	SELECT record, metric, text(datum) FROM measure_date;
COMMENT ON VIEW "measure_view" IS 'Data from all measure tables, coerced to text.';

CREATE VIEW "measure_all" ("record", "metric", "datum_text", "datum_number", "datum_date") AS
	SELECT record, metric, datum, NULL::numeric, NULL::date FROM measure_text UNION ALL
	SELECT record, metric, NULL, datum, NULL FROM measure_number UNION ALL
	SELECT record, metric, NULL, NULL, datum FROM measure_date;
COMMENT ON VIEW "measure_all" IS 'Data from all measure tables, coerced to text.';


CREATE TABLE "volume_annotation" (
	"volume" integer NOT NULL References "volume",
	"annotation" integer NOT NULL References "annotation",
	Primary Key ("volume", "annotation")
);
CREATE INDEX ON "volume_annotation" ("annotation");
COMMENT ON TABLE "volume_annotation" IS 'Attachment of annotations to volumes.';

CREATE TABLE "slot_annotation" (
	"slot" integer NOT NULL References "slot",
	"annotation" integer NOT NULL References "annotation",
	Primary Key ("slot", "annotation")
);
CREATE INDEX ON "slot_annotation" ("annotation");
COMMENT ON TABLE "slot_annotation" IS 'Attachment of annotations to slots.';


CREATE FUNCTION "slot_annotations" ("slot" integer) RETURNS SETOF integer LANGUAGE sql STABLE STRICT AS $$
	SELECT annotation 
	  FROM slot_annotation
	  JOIN slot target ON slot_annotation.slot = target.id
	  JOIN slot this ON target <@ this
	 WHERE this.id = $1
$$;

CREATE FUNCTION "volume_annotations" ("volume" integer) RETURNS SETOF integer LANGUAGE sql STABLE STRICT AS $$
	SELECT annotation FROM volume_annotation WHERE volume = $1 UNION ALL
	SELECT annotation FROM slot_annotation
	  JOIN slot ON slot_annotation.slot = slot.id
	  JOIN container ON slot.source = container.id
	 WHERE container.volume = $1
$$;

CREATE FUNCTION "annotation_consent" ("annotation" integer) RETURNS consent LANGUAGE sql STABLE STRICT AS
	$$ SELECT MIN(consent) FROM slot_annotation JOIN slot ON slot = slot.id WHERE annotation = $1 $$;
COMMENT ON FUNCTION "annotation_consent" (integer) IS 'Effective (minimal) consent level granted on the specified annotation.';

CREATE FUNCTION "annotation_daterange" ("annotation" integer) RETURNS daterange LANGUAGE sql STABLE STRICT AS $$
	SELECT daterange(min(date), max(date), '[]') 
	  FROM slot_annotation
	  JOIN slot ON slot = slot.id
	  JOIN container ON slot.source = container.id
	 WHERE annotation = $1
$$;
COMMENT ON FUNCTION "annotation_daterange" (integer) IS 'Range of container dates covered by the given annotation.';

# --- !Downs
;

DROP TABLE "audit" CASCADE;
DROP TYPE audit_action;

DROP FUNCTION "annotation_daterange" (integer);
DROP FUNCTION "annotation_consent" (integer);
DROP TABLE "slot_annotation";
DROP TABLE "volume_annotation";
DROP VIEW "measure_all";
DROP VIEW "measure_view";
DROP TABLE "measure" CASCADE;
DROP TABLE "record_template";
DROP TABLE "metric";
DROP TYPE data_type;
DROP TABLE "record";
DROP TABLE "record_category";
DROP TABLE "comment";
DROP TABLE "annotation";
DROP FUNCTION "annotation_trigger" ();
DROP TYPE "annotation_kind";

DROP TABLE "toplevel_asset";
DROP TABLE "toplevel_slot";
DROP VIEW "asset_duration";
DROP TABLE "container_asset";
DROP TABLE "clip";
DROP TABLE "timeseries";
DROP TABLE "file";
DROP TABLE "timeseries_format";
DROP TABLE "format";
DROP TABLE "asset";
DROP FUNCTION "asset_trigger" ();
DROP TYPE "asset_kind";
DROP TYPE classification;

DROP FUNCTION "slot_consent" (integer);
DROP VIEW "slot_nesting";
DROP TABLE "slot";
DROP TABLE "container";

DROP OPERATOR <@ ("object_segment", "object_segment");
DROP OPERATOR @> ("object_segment", "object_segment");
DROP FUNCTION "object_segment_within" ("object_segment", "object_segment");
DROP FUNCTION "object_segment_contains" ("object_segment", "object_segment");
DROP TABLE "object_segment";
DROP FUNCTION "segment_shift" (segment, interval);
DROP FUNCTION "singleton" (segment);
DROP FUNCTION "singleton" (interval);
DROP FUNCTION "duration" (segment);
DROP FUNCTION "segment" (interval);
DROP TYPE segment;
DROP FUNCTION "interval_mi_epoch" (interval, interval);

DROP FUNCTION "volume_access_check" (integer, integer, permission);
DROP TABLE "volume_access";
DROP TABLE "volume";

DROP FUNCTION "authorize_delegate_check" (integer, integer, permission);
DROP FUNCTION "authorize_access_check" (integer, integer, permission);
DROP FUNCTION "authorize_access_parents" (integer, permission);
DROP VIEW "authorize_valid";
DROP TABLE "authorize";
DROP TYPE consent;
DROP TYPE permission;
DROP TABLE "account";
DROP TABLE "party";

DROP FUNCTION singleton (int4);
DROP FUNCTION cast_int (text);
DROP FUNCTION create_abstract_parent (name, name[]);
