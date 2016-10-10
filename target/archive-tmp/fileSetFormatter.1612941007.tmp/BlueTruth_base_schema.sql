--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: _final_double_median(anyarray); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION _final_double_median(anyarray) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$
  WITH q AS
  (
     SELECT val
     FROM unnest($1) val
     WHERE VAL IS NOT NULL
     ORDER BY 1
  ),
  cnt AS
  (
    SELECT COUNT(*) AS c FROM q
  )
  SELECT AVG(val)--::float8
  FROM
  (
    SELECT val FROM q
    LIMIT  2 - MOD((SELECT c FROM cnt), 2)
    OFFSET GREATEST(CEIL((SELECT c FROM cnt) / 2.0) - 1,0)
  ) q2;
$_$;


ALTER FUNCTION public._final_double_median(anyarray) OWNER TO bluetruth;

--
-- Name: _final_interval_median(anyarray); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION _final_interval_median(anyarray) RETURNS interval
    LANGUAGE sql IMMUTABLE
    AS $_$
  WITH q AS
  (
     SELECT val
     FROM unnest($1) val
     WHERE VAL IS NOT NULL
     ORDER BY 1
  ),
  cnt AS
  (
    SELECT COUNT(*) AS c FROM q
  )
  SELECT AVG(val)--::float8
  FROM
  (
    SELECT val FROM q
    LIMIT  2 - MOD((SELECT c FROM cnt), 2)
    OFFSET GREATEST(CEIL((SELECT c FROM cnt) / 2.0) - 1,0)
  ) q2;
$_$;


ALTER FUNCTION public._final_interval_median(anyarray) OWNER TO bluetruth;

--
-- Name: _final_median(anyarray); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION _final_median(anyarray) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
  WITH q AS
  (
     SELECT val
     FROM unnest($1) val
     WHERE VAL IS NOT NULL
     ORDER BY 1
  ),
  cnt AS
  (
    SELECT COUNT(*) AS c FROM q
  )
  SELECT AVG(val)--::float8
  FROM
  (
    SELECT val FROM q
    LIMIT  2 - MOD((SELECT c FROM cnt), 2)
    OFFSET GREATEST(CEIL((SELECT c FROM cnt) / 2.0) - 1,0)
  ) q2;
$_$;


ALTER FUNCTION public._final_median(anyarray) OWNER TO bluetruth;

--
-- Name: after_insert_on_detector(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION after_insert_on_detector() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	begin
		IF (TG_OP = 'INSERT') THEN
			INSERT INTO detector_configuration (detector_id) VALUES (NEW.detector_id);
			INSERT INTO detector_statistic (detector_id) VALUES (NEW.detector_id);
			INSERT INTO detector_last_rnd (detector_id) VALUES (NEW.detector_id);
			INSERT INTO detector_status (detector_id) VALUES (NEW.detector_id);
		END IF;
		RETURN NEW;
	END;
$$;


ALTER FUNCTION public.after_insert_on_detector() OWNER TO bluetruth;

--
-- Name: after_insert_on_span(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION after_insert_on_span() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	BEGIN		
		INSERT INTO span_journey_average_duration(span_name) VALUES(NEW.span_name);
		INSERT INTO span_osrm (span_name) VALUES (NEW.span_name);  
		INSERT INTO span_speed_thresholds (span_name) VALUES (NEW.span_name); 
		INSERT INTO span_statistic (span_name, last_journey_detection_timestamp) VALUES (NEW.span_name, null);  
		RETURN NEW;
	END;
$$;


ALTER FUNCTION public.after_insert_on_span() OWNER TO bluetruth;

--
-- Name: after_insert_on_span_journey_detection(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION after_insert_on_span_journey_detection() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
	calculations					record;	
	mode_duration_calculation 			record;
	query_max_data_points				integer;
	query_time_interval				interval;
	durations					interval[];
    BEGIN 
   	
	query_max_data_points = 32;
	query_time_interval := '00:15:00'::interval;
	 
	SELECT INTO durations 
		array(SELECT duration
		FROM span_journey_detection_cache AS sjd
		WHERE sjd.span_name = NEW.span_name
		AND sjd.completed_timestamp > NEW.completed_timestamp - query_time_interval
		AND sjd.outlier = false
		ORDER BY sjd.completed_timestamp DESC
		LIMIT query_max_data_points);

	SELECT INTO calculations AVG(durations_1.duration) AS mean_duration, median_interval(durations_1.duration) AS median_duration
		FROM 
		(SELECT unnest(durations) AS duration) durations_1		
		LIMIT 1;

	SELECT INTO mode_duration_calculation AVG(duration_buckets.duration) AS duration, SUM(duration_buckets.duration_count) AS duration_count, duration_buckets.bucket
	 FROM
	 (
	  SELECT duration, COUNT(duration) AS duration_count, width_bucket(EXTRACT(EPOCH FROM duration), min, max+1, 10) AS bucket
	  FROM
	  (
		  SELECT duration, min, max
		  FROM
		  (SELECT unnest(durations) AS duration) durations_2,
		  (
			SELECT MIN(EXTRACT(EPOCH FROM duration)) AS min, MAX(EXTRACT(EPOCH FROM duration)) AS max
			FROM (SELECT unnest(durations) AS duration) durations_3
		  ) span_journey_detection_range		  
	  ) x
	  GROUP BY duration, min, max
	 ) duration_buckets	
	 GROUP BY duration_buckets.bucket
	 ORDER BY duration_count DESC, duration ASC
	 LIMIT 1;
	
	INSERT INTO span_journey_detection_analytics(
		span_journey_detection_id, 
		span_name, 
		duration_mean, 
		duration_median, 
		duration_mode,
		duration_calculation_strength)
	VALUES (
		NEW.span_journey_detection_id,
		NEW.span_name,
		calculations.mean_duration,
		calculations.median_duration,
		mode_duration_calculation.duration,
		array_length(durations,1)); 

	UPDATE span_statistic 
	SET 
	last_journey_detection_timestamp = NEW.completed_timestamp, 
	last_reported_journey_time = calculations.median_duration,
	last_reported_journey_time_strength = array_length(durations,1)
	WHERE span_name = NEW.span_name;  

	
        RETURN NEW;
    END;
$$;


ALTER FUNCTION public.after_insert_on_span_journey_detection() OWNER TO bluetruth;

--
-- Name: after_insert_on_statistics_device(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION after_insert_on_statistics_device() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE 
ID character varying;
	BEGIN
		IF (NEW.last_seen IS NOT NULL) THEN
			SELECT detector_id INTO ID FROM statistics_report WHERE report_id = NEW.report_id;
			INSERT INTO device_detection(device_id, detection_timestamp, detector_id) VALUES (NEW.addr, NEW.last_seen, ID);	
		END IF;
		RETURN NEW;
	END;
$$;


ALTER FUNCTION public.after_insert_on_statistics_device() OWNER TO bluetruth;

--
-- Name: after_insert_update_on_detector_status(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION after_insert_update_on_detector_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	begin
		INSERT INTO detector_performance (detector_id, sl_2g_min, sl_2g_avg, sl_2g_max, sl_3g_min, sl_3g_avg, sl_3g_max, pi) 
					VALUES (NEW.detector_id, NEW.sl_2g_min, NEW.sl_2g_avg, NEW.sl_2g_max, NEW.sl_3g_min, NEW.sl_3g_avg, NEW.sl_3g_max, NEW.pi);
		RETURN NEW;
	END;
$$;


ALTER FUNCTION public.after_insert_update_on_detector_status() OWNER TO bluetruth;

--
-- Name: array_without_s(character varying[], character varying); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION array_without_s(character varying[], character varying) RETURNS character varying[]
    LANGUAGE sql IMMUTABLE
    AS $_$select array_agg(e) from unnest($1) as a(e) where $2 <> e;$_$;


ALTER FUNCTION public.array_without_s(character varying[], character varying) OWNER TO bluetruth;

--
-- Name: average_journey_time_within_stddev(integer); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION average_journey_time_within_stddev(current_route_id integer) RETURNS interval
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN average_journey_time_within_stddev(current_route_id, 1);
END;
$$;


ALTER FUNCTION public.average_journey_time_within_stddev(current_route_id integer) OWNER TO bluetruth;

--
-- Name: average_journey_time_within_stddev(integer, integer); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION average_journey_time_within_stddev(current_route_id integer, stddevs integer) RETURNS interval
    LANGUAGE plpgsql
    AS $$DECLARE
	stats record;
BEGIN
	SELECT INTO stats AVG(journey.duration) AS unfiltered_average, STDDEV(extract(EPOCH FROM journey.duration)) AS standard_deviation 
	FROM journey 
	WHERE journey.route_id = current_route_id;
	
	RETURN AVG(journey.duration) 
	FROM journey 
	WHERE journey.route_id = current_route_id 
	AND journey.duration <= stats.unfiltered_average + stddevs * stats.standard_deviation * interval '1 second'
	AND journey.duration >= stats.unfiltered_average - stddevs * stats.standard_deviation * interval '1 second'
	;			
END;
$$;


ALTER FUNCTION public.average_journey_time_within_stddev(current_route_id integer, stddevs integer) OWNER TO bluetruth;

--
-- Name: before_insert_on_span_journey_detection(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION before_insert_on_span_journey_detection() RETURNS trigger
    LANGUAGE plpgsql
    AS $$    DECLARE
	quartiles 		record;
	prev_records		integer;
	prev_records_below_duration_threshold		integer;
	query_max_data_points   integer;
	query_time_interval    	interval;
	upper_fence 		double precision;
    BEGIN

	query_max_data_points := 100;
	query_time_interval := '00:30:00'::interval;

	SELECT INTO quartiles MIN(median_duration) AS q1, MAX(median_duration) AS q3
	FROM (
		SELECT ntile, median(duration_miliseconds) AS median_duration
		FROM (
			SELECT EXTRACT(EPOCH FROM duration) AS duration_miliseconds, ntile(2)
			OVER (ORDER BY duration) AS ntile
			FROM (
				SELECT duration
				FROM span_journey_detection_cache
				WHERE completed_timestamp > NEW.completed_timestamp - query_time_interval
				AND span_name = NEW.span_name
				ORDER BY completed_timestamp DESC
				LIMIT query_max_data_points
			) durations
		) ln_duration_by_quartile
		GROUP BY ntile
		ORDER BY ntile
	) quartiles_tmp;

	upper_fence := ((ln(quartiles.q3) - ln(quartiles.q1)) * 1.5) + ln(quartiles.q3);

	IF(ln(EXTRACT(EPOCH FROM NEW.duration)) > upper_fence) THEN
		NEW.outlier := true;
	--ELSE
	--	prev_records := COUNT(*) FROM span_journey_detection
	--		WHERE span_name = NEW.span_name
	--		AND (completed_timestamp - duration) > (NEW.completed_timestamp - NEW.duration);

	--	prev_records_below_duration_threshold := COUNT(*) FROM span_journey_detection
	--		WHERE span_name = NEW.span_name
	--		AND (completed_timestamp - duration) > (NEW.completed_timestamp - NEW.duration)
	--		AND (EXTRACT(EPOCH from duration) < (EXTRACT(EPOCH from NEW.duration) / 2));

	--	IF (prev_records_below_duration_threshold > 0 and (prev_records_below_duration_threshold >= prev_records / 2))
	--	THEN
	--		NEW.outlier := true;
	--		NEW.ed_outlier := true;
	--	END IF;
	END IF;
        RETURN NEW;
    END;
$$;


ALTER FUNCTION public.before_insert_on_span_journey_detection() OWNER TO bluetruth;

--
-- Name: boolean_to_integer(boolean); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION boolean_to_integer(bool boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$  
BEGIN
	IF (bool) THEN
		RETURN 1;
	ELSE
		RETURN 0;
	END IF;
END;
$$;


ALTER FUNCTION public.boolean_to_integer(bool boolean) OWNER TO bluetruth;

--
-- Name: delete_duplicate_detector_logs(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION delete_duplicate_detector_logs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN 
	DELETE
	FROM detector_log 
	WHERE detector_log.detector_id = NEW.detector_id
	AND detector_log.log_text LIKE SUBSTRING(NEW.log_text FROM 0 FOR 50) || '%'; 
		
        RETURN NEW;        
    END;
$$;


ALTER FUNCTION public.delete_duplicate_detector_logs() OWNER TO bluetruth;

--
-- Name: find_journey(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION find_journey() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE 
	found_span 	record;
	last_found_at_start_detector timestamp;
	last_found_at_end_detector timestamp;
	journey_time 	interval;
BEGIN

last_found_at_end_detector := detection_timestamp 
FROM device_detection 
WHERE device_id = NEW.device_id
AND detector_id = NEW.detector_id
ORDER BY detection_timestamp DESC NULLS FIRST LIMIT 1;

FOR found_span IN SELECT 
	span.span_name,
	span.start_detector_id	
	FROM span 
	WHERE		
	span.end_detector_id = NEW.detector_id

LOOP    

	last_found_at_start_detector := detection_timestamp 
	FROM device_detection 
	WHERE device_id = NEW.device_id
	AND detector_id = found_span.start_detector_id
	ORDER BY detection_timestamp DESC NULLS FIRST LIMIT 1;

	IF(last_found_at_start_detector IS NOT NULL 
	AND NEW.detection_timestamp > last_found_at_start_detector 
	AND (last_found_at_end_detector IS NULL OR 
	(NEW.detection_timestamp > last_found_at_end_detector AND last_found_at_start_detector > last_found_at_end_detector))) THEN
				
		journey_time := NEW.detection_timestamp - last_found_at_start_detector;

		IF(journey_time < '01:00:00'::interval) THEN		
			INSERT INTO span_journey_detection_cache (			
				duration,
				span_name,
				completed_timestamp
			)
			VALUES
			(
				journey_time,
				found_span.span_name,
				NEW.detection_timestamp
			); 
			INSERT INTO span_journey_detection (			
				duration,
				span_name,
				completed_timestamp
			)
			VALUES
			(
				journey_time,
				found_span.span_name,
				NEW.detection_timestamp
			); 			
		END IF;
		
	END IF;  
END LOOP;

UPDATE detector_statistic
SET last_detection_timestamp = NEW.detection_timestamp
WHERE detector_id = NEW.detector_id;

RETURN NEW;

END;

$$;


ALTER FUNCTION public.find_journey() OWNER TO bluetruth;

--
-- Name: find_journey_2_00(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION find_journey_2_00() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE 
	found_span 	record;
	last_seen_at_start_detector timestamp;
	first_seen_at_end_detector timestamp;
	journey_time 	interval;
BEGIN

first_seen_at_end_detector := first_seen 
FROM statistics_device 
WHERE addr = NEW.addr
AND detector_id = NEW.detector_id
ORDER BY first_seen DESC NULLS FIRST LIMIT 1;

FOR found_span IN SELECT 
	span.span_name,
	span.start_detector_id	
	FROM span 
	WHERE		
	span.end_detector_id = NEW.detector_id

LOOP    

	last_seen_at_start_detector := last_seen 
	FROM statistics_device 
	WHERE addr = NEW.addr
	AND detector_id = found_span.start_detector_id
	ORDER BY last_seen DESC NULLS FIRST LIMIT 1;

	IF(last_seen_at_start_detector IS NOT NULL 
	AND NEW.first_seen > last_seen_at_start_detector 
	AND (first_seen_at_end_detector IS NULL OR 
	(NEW.first_seen > first_seen_at_end_detector AND last_seen_at_start_detector > first_seen_at_end_detector))) THEN
				
		journey_time := NEW.first_seen - last_seen_at_start_detector;

		IF(journey_time < '01:00:00'::interval) THEN		
			INSERT INTO span_journey_detection_cache (			
				duration,
				span_name,
				completed_timestamp
			)
			VALUES
			(
				journey_time,
				found_span.span_name,
				NEW.first_seen
			); 
			INSERT INTO span_journey_detection (			
				duration,
				span_name,
				completed_timestamp
			)
			VALUES
			(
				journey_time,
				found_span.span_name,
				NEW.first_seen
			); 			
		END IF;
		
	END IF;  
END LOOP;

UPDATE detector_statistic
SET last_detection_timestamp = NEW.last_seen
WHERE detector_id = NEW.detector_id;

RETURN NEW;


END;

$$;


ALTER FUNCTION public.find_journey_2_00() OWNER TO bluetruth;

--
-- Name: floor_minutes(timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION floor_minutes(timestamp with time zone, integer) RETURNS timestamp with time zone
    LANGUAGE sql
    AS $_$ 
  SELECT date_trunc('hour', $1) + $2 * '1 min'::interval * FLOOR(date_part('minute', $1) / $2) 
$_$;


ALTER FUNCTION public.floor_minutes(timestamp with time zone, integer) OWNER TO bluetruth;

--
-- Name: get_average_journey_time(text); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION get_average_journey_time(span_name_in text) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
	DECLARE 
		returned_row RECORD;
        BEGIN
		
	SELECT INTO returned_row avg(span_journey_detection.duration) AS avg, count(span_journey_detection.span_journey_detection_id) AS count
	FROM span_journey_detection 
	WHERE span_journey_detection.completed_timestamp > (now() - '00:05:00'::interval)
	AND span_journey_detection.span_name = span_name_in;  
	  
	IF FOUND THEN
		RETURN NEXT returned_row;	
	END IF;
               
        END;
$$;


ALTER FUNCTION public.get_average_journey_time(span_name_in text) OWNER TO bluetruth;

--
-- Name: insert_historic_copy(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION insert_historic_copy() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

INSERT INTO device_detection_historic(device_id, detection_timestamp, detector_id)
    VALUES (NEW.device_id, NEW.detection_timestamp, NEW.detector_id);
  

RETURN NEW;

END;

$$;


ALTER FUNCTION public.insert_historic_copy() OWNER TO bluetruth;

--
-- Name: insert_span_journey_average_duration_row(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION insert_span_journey_average_duration_row() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
INSERT INTO span_journey_average_duration(span_name) VALUES(NEW.span_name);
RETURN NEW;
END;$$;


ALTER FUNCTION public.insert_span_journey_average_duration_row() OWNER TO bluetruth;

--
-- Name: insert_update_on_detector(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION insert_update_on_detector() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        already_exists boolean;
    BEGIN 
	already_exists := EXISTS(SELECT detector_id FROM detector WHERE detector_id = NEW.detector_id);           
        IF (TG_OP = 'UPDATE' AND already_exists) THEN
		IF (NEW.detector_id <> OLD.detector_id) THEN
			RAISE EXCEPTION 'Detector with ID:[%] already exists.', NEW.detector_id;
		END IF;
        ELSIF (TG_OP = 'INSERT' AND already_exists) THEN
            RAISE EXCEPTION 'Detector with ID:[%] already exists.', NEW.detector_id;
        END IF;
        RETURN NEW;
    END;
$$;


ALTER FUNCTION public.insert_update_on_detector() OWNER TO bluetruth;

--
-- Name: insert_update_on_span(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION insert_update_on_span() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        already_exists boolean;
    BEGIN 
	already_exists := EXISTS(SELECT span_name FROM span WHERE start_detector_id = NEW.start_detector_id AND end_detector_id = NEW.end_detector_id);           
        IF TG_OP = 'UPDATE' THEN
		IF already_exists THEN
			IF (NEW.start_detector_id <> OLD.start_detector_id OR NEW.end_detector_id <> OLD.end_detector_id) THEN
				RAISE EXCEPTION 'Span with specified start and end detectors already exists.';
			END IF;
		ELSIF NEW.span_name IS NULL THEN
			RAISE EXCEPTION 'A name must be given for this span.';	
		ELSIF NEW.start_detector_id = NEW.end_detector_id THEN
			RAISE EXCEPTION 'Start and end detector must be different.';		
		END IF;
        ELSIF TG_OP = 'INSERT' THEN		
		IF already_exists THEN
			RAISE EXCEPTION 'Span with specified start and end detectors already exists.';
		ELSIF NEW.span_name IS NULL THEN
			RAISE EXCEPTION 'A name must be given for this span.';
		ELSIF NEW.start_detector_id = NEW.end_detector_id THEN
			RAISE EXCEPTION 'Start and end detector must be different.';
		END IF;
        END IF;        
        RETURN NEW;
    END;
$$;


ALTER FUNCTION public.insert_update_on_span() OWNER TO bluetruth;

--
-- Name: refresh_span_journey_time_on_update(); Type: FUNCTION; Schema: public; Owner: bluetruth
--

CREATE FUNCTION refresh_span_journey_time_on_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	refresh_interval interval;	
        update_needed boolean;
	returned_row record;
    BEGIN 
	--refesh interval determines how often the average journey time for a span is recalculated.
	refresh_interval := '00:00:05'::interval;
	update_needed := OLD.calculated_timestamp < (now() - refresh_interval) OR OLD.calculated_timestamp IS NULL;  
        IF (update_needed) THEN
		
		SELECT INTO returned_row avg(span_journey_detection.duration) AS average_duration, count(span_journey_detection.span_journey_detection_id) AS strength_count
		FROM span_journey_detection 
		WHERE span_journey_detection.completed_timestamp > (now() - '00:05:00'::interval)
		AND span_journey_detection.span_name = OLD.span_name;

		NEW.duration := returned_row.average_duration;
		NEW.strength_count := returned_row.strength_count;

		RETURN NEW; 
        END IF;
        RETURN OLD;
    END;
$$;


ALTER FUNCTION public.refresh_span_journey_time_on_update() OWNER TO bluetruth;

--
-- Name: median(double precision); Type: AGGREGATE; Schema: public; Owner: bluetruth
--

CREATE AGGREGATE median(double precision) (
    SFUNC = array_append,
    STYPE = double precision[],
    INITCOND = '{}',
    FINALFUNC = _final_double_median
);


ALTER AGGREGATE public.median(double precision) OWNER TO bluetruth;

--
-- Name: median(numeric); Type: AGGREGATE; Schema: public; Owner: bluetruth
--

CREATE AGGREGATE median(numeric) (
    SFUNC = array_append,
    STYPE = numeric[],
    INITCOND = '{}',
    FINALFUNC = _final_median
);


ALTER AGGREGATE public.median(numeric) OWNER TO bluetruth;

--
-- Name: median_interval(interval); Type: AGGREGATE; Schema: public; Owner: bluetruth
--

CREATE AGGREGATE median_interval(interval) (
    SFUNC = array_append,
    STYPE = interval[],
    INITCOND = '{}',
    FINALFUNC = _final_interval_median
);


ALTER AGGREGATE public.median_interval(interval) OWNER TO bluetruth;

--
-- Name: audit_trail_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE audit_trail_id_seq
    START WITH 200
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE audit_trail_id_seq OWNER TO bluetruth;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: audit_trail; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE audit_trail (
    audit_trail_id integer DEFAULT nextval('audit_trail_id_seq'::regclass) NOT NULL,
    username character varying NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    action_type character varying NOT NULL,
    description character varying
);


ALTER TABLE audit_trail OWNER TO bluetruth;

--
-- Name: audit_trail_action; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE audit_trail_action (
    action_type character varying NOT NULL
);


ALTER TABLE audit_trail_action OWNER TO bluetruth;

--
-- Name: branding; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE branding (
    brand character varying NOT NULL,
    css_url character varying,
    website_address character varying
);


ALTER TABLE branding OWNER TO bluetruth;

--
-- Name: branding_contact_details; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE branding_contact_details (
    brand character varying NOT NULL,
    title character varying NOT NULL,
    contact character varying,
    description character varying,
    contact_method character varying NOT NULL
);


ALTER TABLE branding_contact_details OWNER TO bluetruth;

--
-- Name: broadcast_message_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE broadcast_message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE broadcast_message_id_seq OWNER TO bluetruth;

--
-- Name: broadcast_message; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE broadcast_message (
    message_id integer DEFAULT nextval('broadcast_message_id_seq'::regclass) NOT NULL,
    title character varying NOT NULL,
    message character varying NOT NULL
);


ALTER TABLE broadcast_message OWNER TO bluetruth;

--
-- Name: broadcast_message_logical_group; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE broadcast_message_logical_group (
    message_id integer NOT NULL,
    logical_group character varying NOT NULL
);


ALTER TABLE broadcast_message_logical_group OWNER TO bluetruth;

--
-- Name: cmd_queue_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE cmd_queue_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2000000000
    CACHE 1;


ALTER TABLE cmd_queue_seq OWNER TO bluetruth;

--
-- Name: command_queue; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE command_queue (
    id integer DEFAULT nextval('cmd_queue_seq'::regclass) NOT NULL,
    argument character varying,
    name character varying,
    detector_id character varying,
    "time" timestamp with time zone DEFAULT now()
);


ALTER TABLE command_queue OWNER TO bluetruth;

--
-- Name: detector_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE detector_id_seq
    START WITH 10000
    INCREMENT BY 1
    MINVALUE 10000
    NO MAXVALUE
    CACHE 1;


ALTER TABLE detector_id_seq OWNER TO bluetruth;

--
-- Name: detector; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector (
    detector_id character varying NOT NULL,
    detector_name character varying DEFAULT 'default'::character varying,
    mode integer DEFAULT 3 NOT NULL,
    carriageway character varying(5) DEFAULT 'A'::character varying,
    location character varying DEFAULT 'default'::character varying,
    latitude double precision,
    longitude double precision,
    detector_description character varying DEFAULT 'No detector information available'::character varying,
    id integer DEFAULT nextval('detector_id_seq'::regclass) NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE detector OWNER TO bluetruth;

--
-- Name: detector_configuration; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_configuration (
    detector_id character varying NOT NULL,
    "pathToLocalLogFile" character varying(50) DEFAULT '\Hard Disk\'::character varying NOT NULL,
    "localLogFileName" character varying(20) DEFAULT 'log.txt'::character varying NOT NULL,
    "pathLocalIniFile" character varying(50) DEFAULT '\Hard Disk\'::character varying NOT NULL,
    "iniFileLocalName" character varying(30) DEFAULT ''::character varying NOT NULL,
    "urlCongestionReporting" character varying(150) DEFAULT ''::character varying NOT NULL,
    "urlJourneyTimesReporting" character varying(150) DEFAULT ''::character varying NOT NULL,
    "urlLogFileUpload" character varying(150) DEFAULT ''::character varying NOT NULL,
    "urlIniFileDownload" character varying(150) DEFAULT ''::character varying NOT NULL,
    "alertTarget1" character varying DEFAULT ''::character varying NOT NULL,
    "alertTarget2" character varying DEFAULT ''::character varying NOT NULL,
    "alertTarget3" character varying DEFAULT ''::character varying NOT NULL,
    "pingTestAddress" character varying(100) DEFAULT ''::character varying NOT NULL,
    "pingTestTimeout" integer DEFAULT 3000 NOT NULL,
    "heartBeatPeriod" integer DEFAULT 1440 NOT NULL,
    "sendGpsData" boolean DEFAULT false NOT NULL,
    "hysteresisInterval" integer DEFAULT 0 NOT NULL,
    "httpTimeOut" integer DEFAULT 30 NOT NULL,
    "commsFailBufferTimeLimit" integer DEFAULT 60 NOT NULL,
    "debugMode" boolean DEFAULT false NOT NULL,
    "upLoadErrs" boolean DEFAULT false NOT NULL,
    "requestLogs" boolean DEFAULT false NOT NULL,
    "rebootDevice" boolean DEFAULT false NOT NULL,
    "startIdleDate" timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
    "stopIdleDate" timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
    "idleDaily" boolean DEFAULT false NOT NULL,
    "idleDailystartTime" time without time zone DEFAULT '00:00:00'::time without time zone NOT NULL,
    "idleDailystopTime" time without time zone DEFAULT '00:00:00'::time without time zone NOT NULL,
    "daysToIgnore" character varying(170) DEFAULT ''::character varying NOT NULL,
    lanes integer DEFAULT 3 NOT NULL,
    "lengthOfRoad" integer DEFAULT 100 NOT NULL,
    "averageLengthOfVehicle" integer DEFAULT 5 NOT NULL,
    "headwayFree" integer DEFAULT 63 NOT NULL,
    "headwayMod" integer DEFAULT 45 NOT NULL,
    "headwaySlow" integer DEFAULT 9 NOT NULL,
    "headwayVSlow" integer DEFAULT 4 NOT NULL,
    "headwayNrStat" integer DEFAULT 2 NOT NULL,
    "speedBinFree" integer DEFAULT 0 NOT NULL,
    "speedBinMod" integer DEFAULT 0 NOT NULL,
    "speedBinSlow" integer DEFAULT 0 NOT NULL,
    "speedBinVSlow" integer DEFAULT 0 NOT NULL,
    "speedBinNrStat" integer DEFAULT 0 NOT NULL,
    "heavyOccupancyThreshold" double precision DEFAULT 1.0 NOT NULL,
    "moderateOccupancyThreshold" double precision DEFAULT 1.0 NOT NULL,
    "lightOccupancyThreshold" double precision DEFAULT 1.0 NOT NULL,
    "inquiryCyclePeriod" integer DEFAULT 10 NOT NULL,
    "queueDetectThreshold" integer DEFAULT 10 NOT NULL,
    "defaultStaticCyclesThreshold" integer DEFAULT 10 NOT NULL,
    "staticSpeedCyclesThreshold" integer DEFAULT 10 NOT NULL,
    "verySlowSpeedCyclesThreshold" integer DEFAULT 10 NOT NULL,
    "slowSpeedCyclesThreshold" integer DEFAULT 10 NOT NULL,
    "moderateSpeedCyclesThreshold" integer DEFAULT 10 NOT NULL,
    "freeFlowSpeedCyclesThreshold" integer DEFAULT 10 NOT NULL,
    "deviceDiscoveryMaxDevices" integer DEFAULT 246 NOT NULL,
    "settingsCollectionInterval1" integer DEFAULT 15 NOT NULL,
    "settingsCollectionInterval2" integer DEFAULT 15 NOT NULL,
    "checkForUpdates" integer DEFAULT 24 NOT NULL,
    "urlAlertAndStatusReports" character varying(150) DEFAULT ''::character varying NOT NULL,
    "failedIniFileReadRetryCounterThr" integer DEFAULT 3 NOT NULL,
    "includePhoneTypes" boolean DEFAULT true NOT NULL,
    "signatureAveragingCountMax" integer DEFAULT 10 NOT NULL,
    "speedSystem" character varying(4) DEFAULT 'MPH'::character varying NOT NULL,
    "reportedOccupancyFormat" character varying(1) DEFAULT 0 NOT NULL,
    seed integer,
    "urlCongestionReports" character varying DEFAULT ''::character varying NOT NULL,
    "urlStatusReports" character varying DEFAULT ''::character varying NOT NULL,
    "urlFaultReports" character varying DEFAULT ''::character varying NOT NULL,
    "urlStatisticsReports" character varying DEFAULT ''::character varying NOT NULL,
    "inquiryCycleDurationInSeconds" integer DEFAULT 10 NOT NULL,
    "inquiryPower" integer DEFAULT 20 NOT NULL,
    "obfuscatingFunction" integer DEFAULT 0 NOT NULL,
    "statisticsReportPeriodInSeconds" integer DEFAULT 60 NOT NULL,
    "congestionReportPeriodInSeconds" integer DEFAULT 60 NOT NULL,
    "statusReportPeriodInSeconds" integer DEFAULT 600 NOT NULL,
    "backgroundLatchTimeThresholdInSeconds" integer,
    "backgroundClearanceTimeThresholdInSeconds" integer,
    "absenceThresholdInSeconds" integer,
    "queueDetectionStartupIntervalInSeconds" integer,
    "httpResponseTimeOutInSeconds" integer DEFAULT 15 NOT NULL,
    "httpConnectionTimeOutInSeconds" integer DEFAULT 300 NOT NULL,
    "gsmModemSignalLevelSamplingPeriodInSeconds" integer DEFAULT 30 NOT NULL,
    "gsmModemSignalLevelStatisticsWindowInSeconds" integer DEFAULT 300 NOT NULL,
    "ntpServer" character varying DEFAULT 'ntp.bluetruth.co.uk'::character varying NOT NULL,
    "queueAlertThresholdBin" character varying,
    "queueClearanceThreshold" integer,
    "signReports" boolean DEFAULT true NOT NULL
);


ALTER TABLE detector_configuration OWNER TO bluetruth;

--
-- Name: configuration_view_version_1_50; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW configuration_view_version_1_50 AS
 SELECT d.location AS "Location",
    d.detector_name AS "OutStationName",
    d.detector_id AS "outstationID",
    d.carriageway,
    d.mode AS "OutStationMode",
    dc."pathToLocalLogFile",
    dc."localLogFileName",
    dc."pathLocalIniFile",
    dc."iniFileLocalName",
    dc."urlCongestionReporting",
    dc."urlJourneyTimesReporting",
    dc."urlLogFileUpload",
    dc."urlIniFileDownload" AS "urlIniFileDwnload",
    dc."alertTarget1",
    dc."alertTarget2",
    dc."alertTarget3",
    dc."pingTestAddress",
    dc."pingTestTimeout",
    dc."heartBeatPeriod",
    boolean_to_integer(dc."sendGpsData") AS "sendGpsData",
    dc."hysteresisInterval" AS "hysterisisInterval",
    dc."httpTimeOut",
    dc."commsFailBufferTimeLimit",
    boolean_to_integer(dc."debugMode") AS "debugMode",
    boolean_to_integer(dc."upLoadErrs") AS "upLoadErrs",
    boolean_to_integer(dc."requestLogs") AS "requestLogs",
    boolean_to_integer(dc."rebootDevice") AS "rebootDevice",
    dc."startIdleDate" AS "startIdlleDate",
    dc."stopIdleDate",
    boolean_to_integer(dc."idleDaily") AS "idleDaily",
    dc."idleDailystartTime",
    dc."idleDailystopTime",
    dc."daysToIgnore",
    dc.lanes,
    dc."lengthOfRoad",
    dc."averageLengthOfVehicle",
    dc."heavyOccupancyThreshold",
    dc."moderateOccupancyThreshold",
    dc."lightOccupancyThreshold",
    dc."inquiryCyclePeriod",
    dc."queueDetectThreshold" AS "queueDetectThr",
    dc."defaultStaticCyclesThreshold",
    dc."staticSpeedCyclesThreshold",
    dc."verySlowSpeedCyclesThreshold",
    dc."slowSpeedCyclesThreshold",
    dc."moderateSpeedCyclesThreshold",
    dc."freeFlowSpeedCyclesThreshold",
    dc."deviceDiscoveryMaxDevices",
    dc."settingsCollectionInterval1",
    dc."settingsCollectionInterval2",
    dc."checkForUpdates",
    dc."urlAlertAndStatusReports" AS "urlStandAloneReporting",
    dc."failedIniFileReadRetryCounterThr",
    dc."signatureAveragingCountMax",
    dc."headwayFree" AS "headwayAt70",
    dc."headwayMod" AS "headwayAt50",
    dc."headwaySlow" AS "headwayAt30",
    dc."headwayVSlow" AS "headwayAt20",
    dc."headwayNrStat" AS "headwayAt10",
    boolean_to_integer(dc."includePhoneTypes") AS "includePhoneTypes"
   FROM (detector d
     JOIN detector_configuration dc ON (((d.detector_id)::text = (dc.detector_id)::text)));


ALTER TABLE configuration_view_version_1_50 OWNER TO bluetruth;

--
-- Name: configuration_view_version_1_51; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW configuration_view_version_1_51 AS
 SELECT d.location AS "Location",
    d.detector_name AS "OutStationName",
    d.detector_id AS "outstationID",
    d.carriageway,
    d.mode AS "OutStationMode",
    dc."pathToLocalLogFile",
    dc."localLogFileName",
    dc."pathLocalIniFile",
    dc."iniFileLocalName",
    dc."urlCongestionReporting",
    dc."urlJourneyTimesReporting",
    dc."urlLogFileUpload",
    dc."urlIniFileDownload" AS "urlIniFileDwnload",
    dc."alertTarget1",
    dc."alertTarget2",
    dc."alertTarget3",
    dc."pingTestAddress",
    dc."pingTestTimeout",
    dc."heartBeatPeriod",
    boolean_to_integer(dc."sendGpsData") AS "sendGpsData",
    dc."hysteresisInterval" AS "hysterisisInterval",
    dc."httpTimeOut",
    dc."commsFailBufferTimeLimit",
    boolean_to_integer(dc."debugMode") AS "debugMode",
    boolean_to_integer(dc."upLoadErrs") AS "upLoadErrs",
    boolean_to_integer(dc."requestLogs") AS "requestLogs",
    boolean_to_integer(dc."rebootDevice") AS "rebootDevice",
    dc."startIdleDate" AS "startIdlleDate",
    dc."stopIdleDate",
    boolean_to_integer(dc."idleDaily") AS "idleDaily",
    dc."idleDailystartTime",
    dc."idleDailystopTime",
    dc."daysToIgnore",
    dc.lanes,
    dc."lengthOfRoad",
    dc."averageLengthOfVehicle",
    dc."heavyOccupancyThreshold",
    dc."moderateOccupancyThreshold",
    dc."lightOccupancyThreshold",
    dc."inquiryCyclePeriod",
    dc."queueDetectThreshold" AS "queueDetectThr",
    dc."defaultStaticCyclesThreshold",
    dc."staticSpeedCyclesThreshold",
    dc."verySlowSpeedCyclesThreshold",
    dc."slowSpeedCyclesThreshold",
    dc."moderateSpeedCyclesThreshold",
    dc."freeFlowSpeedCyclesThreshold",
    dc."deviceDiscoveryMaxDevices",
    dc."settingsCollectionInterval1",
    dc."settingsCollectionInterval2",
    dc."checkForUpdates",
    dc."urlAlertAndStatusReports" AS "urlStandAloneReporting",
    dc."failedIniFileReadRetryCounterThr",
    dc."signatureAveragingCountMax",
    dc."headwayFree" AS "headwayAt70",
    dc."headwayMod" AS "headwayAt50",
    dc."headwaySlow" AS "headwayAt30",
    dc."headwayVSlow" AS "headwayAt20",
    dc."headwayNrStat" AS "headwayAt10",
    dc."speedBinFree" AS "binFree",
    dc."speedBinMod" AS "binMod",
    dc."speedBinSlow" AS "binSlow"
   FROM (detector d
     JOIN detector_configuration dc ON (((d.detector_id)::text = (dc.detector_id)::text)));


ALTER TABLE configuration_view_version_1_51 OWNER TO bluetruth;

--
-- Name: configuration_view_version_2_00; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW configuration_view_version_2_00 AS
 SELECT d.mode AS "outStationMode",
    dc."urlCongestionReports",
    dc."urlStatusReports",
    dc."urlFaultReports",
    dc."urlStatisticsReports",
    dc."inquiryCyclePeriod" AS "inquiryCycleDurationInSeconds",
    dc."inquiryPower",
    dc."obfuscatingFunction",
    dc."statisticsReportPeriodInSeconds",
    dc."congestionReportPeriodInSeconds",
    dc."statusReportPeriodInSeconds",
    dc."backgroundLatchTimeThresholdInSeconds",
    dc."backgroundClearanceTimeThresholdInSeconds",
    dc."freeFlowSpeedCyclesThreshold" AS "freeFlowBinThresholdInSeconds",
    dc."moderateSpeedCyclesThreshold" AS "moderateFlowBinThresholdInSeconds",
    dc."verySlowSpeedCyclesThreshold" AS "verySlowFlowBinThresholdInSeconds",
    dc."absenceThresholdInSeconds",
    dc."queueAlertThresholdBin",
    dc."queueDetectThreshold",
    dc."queueClearanceThreshold",
    dc."queueDetectionStartupIntervalInSeconds",
    boolean_to_integer(dc."signReports") AS "signReports",
    dc."httpResponseTimeOutInSeconds",
    dc."httpConnectionTimeOutInSeconds",
    dc."ntpServer",
    dc."gsmModemSignalLevelSamplingPeriodInSeconds",
    dc."gsmModemSignalLevelStatisticsWindowInSeconds",
    d.location AS "Location",
    d.detector_name AS "OutStationName",
    d.detector_id AS "outstationID",
    d.carriageway,
    dc."pathToLocalLogFile",
    dc."localLogFileName",
    dc."pathLocalIniFile",
    dc."iniFileLocalName",
    dc."urlLogFileUpload",
    dc."urlIniFileDownload",
    dc."alertTarget1",
    dc."alertTarget2",
    dc."alertTarget3",
    dc."pingTestAddress",
    dc."pingTestTimeout",
    dc."heartBeatPeriod",
    boolean_to_integer(dc."sendGpsData") AS "sendGpsData",
    dc."hysteresisInterval",
    dc."httpTimeOut",
    dc."commsFailBufferTimeLimit",
    boolean_to_integer(dc."debugMode") AS "debugMode",
    boolean_to_integer(dc."upLoadErrs") AS "upLoadErrs",
    boolean_to_integer(dc."requestLogs") AS "requestLogs",
    boolean_to_integer(dc."rebootDevice") AS "rebootDevice",
    dc."startIdleDate",
    dc."stopIdleDate",
    boolean_to_integer(dc."idleDaily") AS "idleDaily",
    dc."idleDailystartTime",
    dc."idleDailystopTime",
    dc."daysToIgnore",
    dc.lanes,
    dc."lengthOfRoad",
    dc."averageLengthOfVehicle",
    dc."headwayFree",
    dc."headwayMod",
    dc."headwaySlow",
    dc."headwayVSlow",
    dc."headwayNrStat",
    dc."speedBinFree",
    dc."speedBinMod",
    dc."speedBinSlow",
    dc."speedBinVSlow",
    dc."speedBinNrStat",
    dc."heavyOccupancyThreshold",
    dc."moderateOccupancyThreshold",
    dc."lightOccupancyThreshold",
    dc."defaultStaticCyclesThreshold",
    dc."staticSpeedCyclesThreshold",
    dc."slowSpeedCyclesThreshold" AS "slowFlowBinThresholdInSeconds",
    dc."deviceDiscoveryMaxDevices",
    dc."settingsCollectionInterval1",
    dc."settingsCollectionInterval2",
    dc."checkForUpdates",
    dc."failedIniFileReadRetryCounterThr",
    boolean_to_integer(dc."includePhoneTypes") AS "includePhoneTypes",
    dc."signatureAveragingCountMax",
    dc."speedSystem",
    dc."reportedOccupancyFormat"
   FROM (detector d
     JOIN detector_configuration dc ON (((d.detector_id)::text = (dc.detector_id)::text)));


ALTER TABLE configuration_view_version_2_00 OWNER TO bluetruth;

--
-- Name: detector_confirmed_config; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_confirmed_config (
    detector_id character varying NOT NULL,
    seed_id integer,
    of_id integer
);


ALTER TABLE detector_confirmed_config OWNER TO bluetruth;

--
-- Name: detector_engineer_notes_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE detector_engineer_notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE detector_engineer_notes_id_seq OWNER TO bluetruth;

--
-- Name: detector_engineer_notes; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_engineer_notes (
    note_id integer DEFAULT nextval('detector_engineer_notes_id_seq'::regclass) NOT NULL,
    detector_id character varying,
    description character varying,
    author character varying,
    added_timestamp timestamp with time zone DEFAULT now()
);


ALTER TABLE detector_engineer_notes OWNER TO bluetruth;

--
-- Name: detector_keys; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_keys (
    detector_id character varying NOT NULL,
    outstation_public character varying
);


ALTER TABLE detector_keys OWNER TO bluetruth;

--
-- Name: detector_last_rnd; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_last_rnd (
    id integer NOT NULL,
    detector_id character varying,
    seed_id integer,
    last_rnd integer DEFAULT 0
);


ALTER TABLE detector_last_rnd OWNER TO bluetruth;

--
-- Name: detector_last_rnd_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE detector_last_rnd_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE detector_last_rnd_id_seq OWNER TO bluetruth;

--
-- Name: detector_last_rnd_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE detector_last_rnd_id_seq OWNED BY detector_last_rnd.id;


--
-- Name: detector_log; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_log (
    detector_log_id integer NOT NULL,
    detector_id character varying NOT NULL,
    uploaded_timestamp timestamp with time zone DEFAULT now() NOT NULL,
    log_text character varying NOT NULL
);


ALTER TABLE detector_log OWNER TO bluetruth;

--
-- Name: detector_log_detector_log_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE detector_log_detector_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE detector_log_detector_log_id_seq OWNER TO bluetruth;

--
-- Name: detector_log_detector_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE detector_log_detector_log_id_seq OWNED BY detector_log.detector_log_id;


--
-- Name: detector_logical_group; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_logical_group (
    detector_id character varying NOT NULL,
    logical_group_name character varying NOT NULL
);


ALTER TABLE detector_logical_group OWNER TO bluetruth;

--
-- Name: detector_message; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_message (
    detector_message_id integer NOT NULL,
    detector_id character varying NOT NULL,
    recorded_timestamp timestamp with time zone NOT NULL,
    code character varying NOT NULL,
    description character varying NOT NULL,
    category character varying NOT NULL,
    description_detail character varying NOT NULL,
    count integer NOT NULL
);


ALTER TABLE detector_message OWNER TO bluetruth;

--
-- Name: detector_message_detector_message_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE detector_message_detector_message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE detector_message_detector_message_id_seq OWNER TO bluetruth;

--
-- Name: detector_message_detector_message_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE detector_message_detector_message_id_seq OWNED BY detector_message.detector_message_id;


--
-- Name: detector_performance; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE detector_performance (
    detector_id character varying NOT NULL,
    detection_timestamp timestamp with time zone DEFAULT now() NOT NULL,
    sl_2g_min integer DEFAULT (-255) NOT NULL,
    sl_2g_avg integer DEFAULT (-255) NOT NULL,
    sl_2g_max integer DEFAULT (-255) NOT NULL,
    sl_3g_min integer DEFAULT (-255) NOT NULL,
    sl_3g_avg integer DEFAULT (-255) NOT NULL,
    sl_3g_max integer DEFAULT (-255) NOT NULL,
    pi integer DEFAULT (-255) NOT NULL
);


ALTER TABLE detector_performance OWNER TO postgres;

--
-- Name: detector_seed; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_seed (
    id integer NOT NULL,
    detector_id character varying NOT NULL,
    seed integer NOT NULL,
    last integer DEFAULT 0 NOT NULL,
    retries integer DEFAULT 0 NOT NULL
);


ALTER TABLE detector_seed OWNER TO bluetruth;

--
-- Name: detector_seed_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE detector_seed_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE detector_seed_id_seq OWNER TO bluetruth;

--
-- Name: detector_seed_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE detector_seed_id_seq OWNED BY detector_seed.id;


--
-- Name: detector_statistic; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_statistic (
    detector_id character varying NOT NULL,
    last_configuration_download_request_timestamp timestamp without time zone,
    last_configuration_download_version character varying,
    last_detection_timestamp timestamp with time zone
);


ALTER TABLE detector_statistic OWNER TO bluetruth;

--
-- Name: detector_status; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_status (
    detector_id character varying NOT NULL,
    fv character varying DEFAULT 'N/A'::character varying,
    sn character varying DEFAULT 'N/A'::character varying,
    cv character varying DEFAULT 'N/A'::character varying,
    of integer,
    ssh character varying DEFAULT 'N/A'::character varying,
    seed integer,
    up integer,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    sl_2g_min integer DEFAULT (-255),
    sl_2g_avg integer DEFAULT (-255),
    sl_2g_max integer DEFAULT (-255),
    sl_3g_min integer DEFAULT (-255),
    sl_3g_avg integer DEFAULT (-255),
    sl_3g_max integer DEFAULT (-255),
    pi integer DEFAULT (-255)
);


ALTER TABLE detector_status OWNER TO bluetruth;

--
-- Name: detector_unconfigured; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE detector_unconfigured (
    detector_id character varying NOT NULL,
    last_configuration_download_request timestamp with time zone,
    last_device_detection timestamp with time zone,
    last_traffic_flow_report timestamp with time zone,
    last_message_report timestamp with time zone,
    last_log_upload timestamp with time zone
);


ALTER TABLE detector_unconfigured OWNER TO bluetruth;

--
-- Name: device_detection; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE device_detection (
    device_detection_id bigint NOT NULL,
    device_id character varying NOT NULL,
    detection_timestamp timestamp with time zone NOT NULL,
    detector_id character varying
);


ALTER TABLE device_detection OWNER TO bluetruth;

--
-- Name: device_detection_historic_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE device_detection_historic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE device_detection_historic_id_seq OWNER TO bluetruth;

--
-- Name: device_detection_historic; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE device_detection_historic (
    device_detection_historic_id bigint DEFAULT nextval('device_detection_historic_id_seq'::regclass) NOT NULL,
    device_id character varying NOT NULL,
    detection_timestamp timestamp with time zone NOT NULL,
    detector_id character varying
);


ALTER TABLE device_detection_historic OWNER TO bluetruth;

--
-- Name: device_detection_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE device_detection_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE device_detection_id_seq OWNER TO bluetruth;

--
-- Name: device_detection_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE device_detection_id_seq OWNED BY device_detection.device_detection_id;


--
-- Name: fault_message_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE fault_message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2000111222
    CACHE 1;


ALTER TABLE fault_message_id_seq OWNER TO bluetruth;

--
-- Name: fault_message; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE fault_message (
    id integer DEFAULT nextval('fault_message_id_seq'::regclass) NOT NULL,
    code integer,
    status integer,
    "time" timestamp with time zone,
    report_id integer
);


ALTER TABLE fault_message OWNER TO bluetruth;

--
-- Name: fault_report_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE fault_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2000111222
    CACHE 1;


ALTER TABLE fault_report_id_seq OWNER TO bluetruth;

--
-- Name: fault_report; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE fault_report (
    report_id integer DEFAULT nextval('fault_report_id_seq'::regclass) NOT NULL,
    "time" timestamp with time zone,
    detector_id character varying
);


ALTER TABLE fault_report OWNER TO bluetruth;

--
-- Name: instation_role; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE instation_role (
    role_name character varying NOT NULL,
    description character varying
);


ALTER TABLE instation_role OWNER TO bluetruth;

--
-- Name: instation_user; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE instation_user (
    full_name character varying,
    username character varying NOT NULL,
    md5_password character varying NOT NULL,
    brand character varying,
    timezone_name character varying,
    activated boolean DEFAULT false,
    email_address character varying NOT NULL,
    activation_key character varying,
    expiry_days integer DEFAULT 30 NOT NULL,
    last_password_update_timestamp timestamp with time zone
);


ALTER TABLE instation_user OWNER TO bluetruth;

--
-- Name: instation_user_authentication; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW instation_user_authentication AS
 SELECT instation_user.full_name,
    instation_user.username,
    instation_user.md5_password,
    instation_user.brand,
    instation_user.timezone_name
   FROM instation_user
  WHERE (instation_user.activated = true);


ALTER TABLE instation_user_authentication OWNER TO bluetruth;

--
-- Name: instation_user_logical_group; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE instation_user_logical_group (
    username character varying NOT NULL,
    logical_group_name character varying NOT NULL
);


ALTER TABLE instation_user_logical_group OWNER TO bluetruth;

--
-- Name: instation_user_role; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE instation_user_role (
    username character varying NOT NULL,
    role_name character varying NOT NULL
);


ALTER TABLE instation_user_role OWNER TO bluetruth;

--
-- Name: instation_user_timezone; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE instation_user_timezone (
    timezone_name character varying NOT NULL
);


ALTER TABLE instation_user_timezone OWNER TO bluetruth;

--
-- Name: instation_user_view; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE instation_user_view (
    full_name character varying,
    username character varying,
    email_address character varying,
    roles text,
    logical_groups text,
    activated boolean
);


ALTER TABLE instation_user_view OWNER TO bluetruth;

--
-- Name: journey_id_cache_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE journey_id_cache_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE journey_id_cache_seq OWNER TO bluetruth;

--
-- Name: span_journey_detection; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_journey_detection (
    span_journey_detection_id integer NOT NULL,
    duration interval NOT NULL,
    completed_timestamp timestamp with time zone,
    span_name character varying,
    outlier boolean DEFAULT false
);


ALTER TABLE span_journey_detection OWNER TO bluetruth;

--
-- Name: journey_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE journey_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE journey_id_seq OWNER TO bluetruth;

--
-- Name: journey_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE journey_id_seq OWNED BY span_journey_detection.span_journey_detection_id;


--
-- Name: journey_time_last_24_hours_view; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW journey_time_last_24_hours_view AS
 SELECT span_journey_detection.span_name,
    (date_part('epoch'::text, span_journey_detection.duration) * (1000)::double precision) AS millisecond_duration,
    (date_trunc('H'::text, span_journey_detection.completed_timestamp) + (date_part('minute'::text, span_journey_detection.completed_timestamp) * '00:01:00'::interval)) AS completed_timestamp_section,
    span_journey_detection.completed_timestamp
   FROM span_journey_detection
  WHERE (((span_journey_detection.duration < '00:10:00'::interval) AND (span_journey_detection.completed_timestamp > ((date_trunc('H'::text, now()) + ((floor((date_part('minute'::text, now()) / (5)::double precision)) * (5)::double precision) * '00:01:00'::interval)) - '24:00:00'::interval))) AND (span_journey_detection.completed_timestamp < (date_trunc('H'::text, now()) + ((floor((date_part('minute'::text, now()) / (5)::double precision)) * (5)::double precision) * '00:01:00'::interval))));


ALTER TABLE journey_time_last_24_hours_view OWNER TO bluetruth;

--
-- Name: journey_time_service_user; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE journey_time_service_user (
    journey_times_cap integer DEFAULT 2000 NOT NULL,
    historic_journey_times_period integer DEFAULT 5 NOT NULL,
    username character varying NOT NULL
);


ALTER TABLE journey_time_service_user OWNER TO bluetruth;

--
-- Name: TABLE journey_time_service_user; Type: COMMENT; Schema: public; Owner: bluetruth
--

COMMENT ON TABLE journey_time_service_user IS 'Users of the JTS can configure the period of the historic journey times in the feed and a cap on the amount of journey times returned per request.';


--
-- Name: COLUMN journey_time_service_user.historic_journey_times_period; Type: COMMENT; Schema: public; Owner: bluetruth
--

COMMENT ON COLUMN journey_time_service_user.historic_journey_times_period IS 'period in minutes';


--
-- Name: logical_group; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE logical_group (
    logical_group_name character varying NOT NULL,
    description character varying
);


ALTER TABLE logical_group OWNER TO bluetruth;

--
-- Name: occupancy; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE occupancy (
    occupancy_id integer NOT NULL,
    detector_id character varying,
    reported_timestamp timestamp with time zone NOT NULL,
    stationary integer,
    very_slow integer,
    slow integer,
    moderate integer,
    free integer,
    queue_start_timestamp timestamp with time zone,
    queue_end_timestamp timestamp with time zone,
    queue_present integer
);


ALTER TABLE occupancy OWNER TO bluetruth;

--
-- Name: most_recent_occupancy_view; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW most_recent_occupancy_view AS
 SELECT detector.detector_id,
    detector.detector_name,
    occupancy.reported_timestamp,
    occupancy.stationary,
    occupancy.very_slow,
    occupancy.slow,
    occupancy.moderate,
    occupancy.free,
        CASE
            WHEN (occupancy.queue_start_timestamp IS NOT NULL) THEN 'QUEUEING'::text
            WHEN (occupancy.queue_end_timestamp IS NOT NULL) THEN 'FREE'::text
            ELSE 'CALCULATING'::text
        END AS queue
   FROM ((detector
     LEFT JOIN occupancy ON (((detector.detector_id)::text = (occupancy.detector_id)::text)))
     JOIN ( SELECT occupancy_1.detector_id,
            max(occupancy_1.reported_timestamp) AS reported_timestamp
           FROM occupancy occupancy_1
          GROUP BY occupancy_1.detector_id) most_recent_occupancy ON (((((detector.detector_id)::text = (most_recent_occupancy.detector_id)::text) AND (occupancy.reported_timestamp = most_recent_occupancy.reported_timestamp)) AND (occupancy.reported_timestamp > (now() - '00:05:00'::interval)))));


ALTER TABLE most_recent_occupancy_view OWNER TO bluetruth;

--
-- Name: occupancy_occupancy_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE occupancy_occupancy_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE occupancy_occupancy_id_seq OWNER TO bluetruth;

--
-- Name: occupancy_occupancy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE occupancy_occupancy_id_seq OWNED BY occupancy.occupancy_id;


--
-- Name: route; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE route (
    route_name character varying NOT NULL,
    description character varying
);


ALTER TABLE route OWNER TO bluetruth;

--
-- Name: route_span; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE route_span (
    route_name character varying NOT NULL,
    span_name character varying NOT NULL
);


ALTER TABLE route_span OWNER TO bluetruth;

--
-- Name: span_journey_average_duration; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_journey_average_duration (
    span_name character varying NOT NULL,
    duration interval,
    strength_count integer,
    calculated_timestamp timestamp with time zone
);


ALTER TABLE span_journey_average_duration OWNER TO bluetruth;

--
-- Name: route_average_duration; Type: VIEW; Schema: public; Owner: bluetruth
--

CREATE VIEW route_average_duration AS
 SELECT route.route_name,
    sum(span_journey_average_duration.duration) AS total_duration,
    sum(span_journey_average_duration.strength_count) AS strength_count,
    sum(
        CASE
            WHEN (span_journey_average_duration.strength_count < 1) THEN 0
            ELSE 1
        END) AS reporting_spans,
    count(span_journey_average_duration.span_name) AS total_spans,
    min(span_journey_average_duration.calculated_timestamp) AS calculated_timestamp
   FROM ((route
     LEFT JOIN route_span ON (((route.route_name)::text = (route_span.route_name)::text)))
     JOIN span_journey_average_duration ON (((route_span.span_name)::text = (span_journey_average_duration.span_name)::text)))
  GROUP BY route.route_name;


ALTER TABLE route_average_duration OWNER TO bluetruth;

--
-- Name: route_datex2_datex2_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE route_datex2_datex2_id_seq
    START WITH 100000
    INCREMENT BY 1
    MINVALUE 100000
    NO MAXVALUE
    CACHE 1;


ALTER TABLE route_datex2_datex2_id_seq OWNER TO bluetruth;

--
-- Name: route_datex2; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE route_datex2 (
    route_name character varying NOT NULL,
    datex2_id integer DEFAULT nextval('route_datex2_datex2_id_seq'::regclass) NOT NULL
);


ALTER TABLE route_datex2 OWNER TO bluetruth;

--
-- Name: route_logical_group; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE route_logical_group (
    logical_group_name character varying NOT NULL,
    route_name character varying NOT NULL
);


ALTER TABLE route_logical_group OWNER TO bluetruth;

--
-- Name: span_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE span_id_seq
    START WITH 10000
    INCREMENT BY 1
    MINVALUE 10000
    NO MAXVALUE
    CACHE 1;


ALTER TABLE span_id_seq OWNER TO bluetruth;

--
-- Name: span; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span (
    span_name character varying NOT NULL,
    start_detector_id character varying,
    end_detector_id character varying,
    id integer DEFAULT nextval('span_id_seq'::regclass) NOT NULL
);


ALTER TABLE span OWNER TO bluetruth;

--
-- Name: span_events_information_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE span_events_information_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE span_events_information_id_seq OWNER TO bluetruth;

--
-- Name: span_events_information; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_events_information (
    event_id integer DEFAULT nextval('span_events_information_id_seq'::regclass) NOT NULL,
    span_name character varying,
    description character varying,
    start_timestamp timestamp with time zone,
    end_timestamp timestamp with time zone
);


ALTER TABLE span_events_information OWNER TO bluetruth;

--
-- Name: span_incidents_information_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE span_incidents_information_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE span_incidents_information_id_seq OWNER TO bluetruth;

--
-- Name: span_incidents_information; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_incidents_information (
    incident_id integer DEFAULT nextval('span_incidents_information_id_seq'::regclass) NOT NULL,
    span_name character varying,
    description character varying,
    start_timestamp timestamp with time zone,
    end_timestamp timestamp with time zone
);


ALTER TABLE span_incidents_information OWNER TO bluetruth;

--
-- Name: span_journey_detection_analyt_span_journey_detection_analyt_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE span_journey_detection_analyt_span_journey_detection_analyt_seq
    START WITH 10
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE span_journey_detection_analyt_span_journey_detection_analyt_seq OWNER TO bluetruth;

--
-- Name: span_journey_detection_analytics; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_journey_detection_analytics (
    span_journey_detection_analytics_id integer DEFAULT nextval('span_journey_detection_analyt_span_journey_detection_analyt_seq'::regclass) NOT NULL,
    span_name character varying,
    span_journey_detection_id integer,
    duration_mode interval,
    duration_mean interval,
    duration_median interval,
    duration_calculation_strength integer DEFAULT 0
);


ALTER TABLE span_journey_detection_analytics OWNER TO bluetruth;

--
-- Name: span_journey_detection_cache; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_journey_detection_cache (
    span_journey_detection_id integer DEFAULT nextval('journey_id_cache_seq'::regclass) NOT NULL,
    duration interval NOT NULL,
    completed_timestamp timestamp with time zone,
    span_name character varying,
    outlier boolean DEFAULT false
);


ALTER TABLE span_journey_detection_cache OWNER TO bluetruth;

--
-- Name: span_logical_group; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_logical_group (
    logical_group_name character varying NOT NULL,
    span_name character varying NOT NULL
);


ALTER TABLE span_logical_group OWNER TO bluetruth;

--
-- Name: span_notes_information_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE span_notes_information_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE span_notes_information_id_seq OWNER TO bluetruth;

--
-- Name: span_notes_information; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_notes_information (
    note_id integer DEFAULT nextval('span_notes_information_id_seq'::regclass) NOT NULL,
    span_name character varying,
    description character varying,
    author character varying,
    added_timestamp timestamp with time zone DEFAULT now()
);


ALTER TABLE span_notes_information OWNER TO bluetruth;

--
-- Name: span_osrm; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_osrm (
    span_name character varying NOT NULL,
    route_geometry character varying,
    total_distance integer DEFAULT 0,
    total_time integer DEFAULT 0
);


ALTER TABLE span_osrm OWNER TO bluetruth;

--
-- Name: span_speed_thresholds; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_speed_thresholds (
    span_name character varying NOT NULL,
    stationary integer DEFAULT 5,
    very_slow integer DEFAULT 10,
    slow integer DEFAULT 20,
    moderate integer DEFAULT 30,
    CONSTRAINT "slowLessThanModerate" CHECK ((slow < moderate)),
    CONSTRAINT "stationaryLessthanVerySlow" CHECK ((stationary < very_slow)),
    CONSTRAINT "verySlowLessThanSlow" CHECK ((very_slow < slow))
);


ALTER TABLE span_speed_thresholds OWNER TO bluetruth;

--
-- Name: span_statistic; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE span_statistic (
    span_name character varying NOT NULL,
    last_journey_detection_timestamp timestamp with time zone,
    last_reported_journey_time interval,
    last_reported_journey_time_strength integer DEFAULT 0
);


ALTER TABLE span_statistic OWNER TO bluetruth;

--
-- Name: statistics_device; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE statistics_device (
    report_id integer NOT NULL,
    cod integer,
    first_seen timestamp with time zone,
    reference_point timestamp with time zone,
    last_seen timestamp with time zone,
    addr character varying,
    id integer NOT NULL,
    detector_id character varying,
    last_detection_timestamp timestamp with time zone
);


ALTER TABLE statistics_device OWNER TO bluetruth;

--
-- Name: statistics_device_report_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE statistics_device_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE statistics_device_report_id_seq OWNER TO bluetruth;

--
-- Name: statistics_device_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bluetruth
--

ALTER SEQUENCE statistics_device_report_id_seq OWNED BY statistics_device.report_id;


--
-- Name: statistics_report_id_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE statistics_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 1000000000
    CACHE 1;


ALTER TABLE statistics_report_id_seq OWNER TO bluetruth;

--
-- Name: statistics_report; Type: TABLE; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE TABLE statistics_report (
    detector_id character varying,
    report_start timestamp with time zone,
    report_end timestamp with time zone,
    report_id integer DEFAULT nextval('statistics_report_id_seq'::regclass) NOT NULL,
    of_id integer
);


ALTER TABLE statistics_report OWNER TO bluetruth;

--
-- Name: status_report_seq; Type: SEQUENCE; Schema: public; Owner: bluetruth
--

CREATE SEQUENCE status_report_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2000111222
    CACHE 1;


ALTER TABLE status_report_seq OWNER TO bluetruth;

--
-- Name: id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_last_rnd ALTER COLUMN id SET DEFAULT nextval('detector_last_rnd_id_seq'::regclass);


--
-- Name: detector_log_id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_log ALTER COLUMN detector_log_id SET DEFAULT nextval('detector_log_detector_log_id_seq'::regclass);


--
-- Name: detector_message_id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_message ALTER COLUMN detector_message_id SET DEFAULT nextval('detector_message_detector_message_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_seed ALTER COLUMN id SET DEFAULT nextval('detector_seed_id_seq'::regclass);


--
-- Name: device_detection_id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY device_detection ALTER COLUMN device_detection_id SET DEFAULT nextval('device_detection_id_seq'::regclass);


--
-- Name: occupancy_id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY occupancy ALTER COLUMN occupancy_id SET DEFAULT nextval('occupancy_occupancy_id_seq'::regclass);


--
-- Name: span_journey_detection_id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_journey_detection ALTER COLUMN span_journey_detection_id SET DEFAULT nextval('journey_id_seq'::regclass);


--
-- Name: report_id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY statistics_device ALTER COLUMN report_id SET DEFAULT nextval('statistics_device_report_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY statistics_device ALTER COLUMN id SET DEFAULT nextval('statistics_device_report_id_seq'::regclass);


--
-- Name: audit_trail_action_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY audit_trail_action
    ADD CONSTRAINT audit_trail_action_pk PRIMARY KEY (action_type);


--
-- Name: audit_trail_id_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY audit_trail
    ADD CONSTRAINT audit_trail_id_pk PRIMARY KEY (audit_trail_id);


--
-- Name: brand_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY branding
    ADD CONSTRAINT brand_pk PRIMARY KEY (brand);


--
-- Name: branding_contact_details_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY branding_contact_details
    ADD CONSTRAINT branding_contact_details_pk PRIMARY KEY (brand, title, contact_method);


--
-- Name: broadcast_message_logical_group_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY broadcast_message_logical_group
    ADD CONSTRAINT broadcast_message_logical_group_pk PRIMARY KEY (message_id, logical_group);


--
-- Name: broadcast_message_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY broadcast_message
    ADD CONSTRAINT broadcast_message_pk PRIMARY KEY (message_id);


--
-- Name: command_queue_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY command_queue
    ADD CONSTRAINT command_queue_pk PRIMARY KEY (id);


--
-- Name: detector_configuration_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_configuration
    ADD CONSTRAINT detector_configuration_pk PRIMARY KEY (detector_id);


--
-- Name: detector_engineer_notes_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_engineer_notes
    ADD CONSTRAINT detector_engineer_notes_pk PRIMARY KEY (note_id);


--
-- Name: detector_id_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_unconfigured
    ADD CONSTRAINT detector_id_pk PRIMARY KEY (detector_id);


--
-- Name: detector_keys_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_keys
    ADD CONSTRAINT detector_keys_pk PRIMARY KEY (detector_id);


--
-- Name: detector_log_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_log
    ADD CONSTRAINT detector_log_pk PRIMARY KEY (detector_log_id);


--
-- Name: detector_logical_group_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_logical_group
    ADD CONSTRAINT detector_logical_group_pk PRIMARY KEY (detector_id, logical_group_name);


--
-- Name: detector_message_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_message
    ADD CONSTRAINT detector_message_pk PRIMARY KEY (detector_message_id);


--
-- Name: detector_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector
    ADD CONSTRAINT detector_pkey PRIMARY KEY (detector_id);


--
-- Name: detector_seed_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_seed
    ADD CONSTRAINT detector_seed_pkey PRIMARY KEY (id);


--
-- Name: detector_statistic_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_statistic
    ADD CONSTRAINT detector_statistic_pk PRIMARY KEY (detector_id);


--
-- Name: detector_status_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY detector_status
    ADD CONSTRAINT detector_status_pkey PRIMARY KEY (detector_id);


--
-- Name: device_detection_historic_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY device_detection_historic
    ADD CONSTRAINT device_detection_historic_pkey PRIMARY KEY (device_detection_historic_id);


--
-- Name: device_detection_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY device_detection
    ADD CONSTRAINT device_detection_pkey PRIMARY KEY (device_detection_id);


--
-- Name: fault_message_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY fault_message
    ADD CONSTRAINT fault_message_pkey PRIMARY KEY (id);


--
-- Name: fault_report_id_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY fault_report
    ADD CONSTRAINT fault_report_id_pk PRIMARY KEY (report_id);


--
-- Name: instation_role_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY instation_role
    ADD CONSTRAINT instation_role_pk PRIMARY KEY (role_name);


--
-- Name: instation_user_logical_group_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY instation_user_logical_group
    ADD CONSTRAINT instation_user_logical_group_pk PRIMARY KEY (username, logical_group_name);


--
-- Name: instation_user_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY instation_user
    ADD CONSTRAINT instation_user_pk PRIMARY KEY (username);


--
-- Name: instation_user_role_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY instation_user_role
    ADD CONSTRAINT instation_user_role_pk PRIMARY KEY (username, role_name);


--
-- Name: instation_user_timezone_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY instation_user_timezone
    ADD CONSTRAINT instation_user_timezone_pk PRIMARY KEY (timezone_name);


--
-- Name: journey_time_service_user_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY journey_time_service_user
    ADD CONSTRAINT journey_time_service_user_pkey PRIMARY KEY (username);


--
-- Name: logical_group_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY logical_group
    ADD CONSTRAINT logical_group_pk PRIMARY KEY (logical_group_name);


--
-- Name: occupancy_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY occupancy
    ADD CONSTRAINT occupancy_pkey PRIMARY KEY (occupancy_id);


--
-- Name: route_datex2_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY route_datex2
    ADD CONSTRAINT route_datex2_pk PRIMARY KEY (route_name, datex2_id);


--
-- Name: route_logical_group_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY route_logical_group
    ADD CONSTRAINT route_logical_group_pk PRIMARY KEY (logical_group_name, route_name);


--
-- Name: route_route_name_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY route
    ADD CONSTRAINT route_route_name_pk PRIMARY KEY (route_name);


--
-- Name: route_span_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY route_span
    ADD CONSTRAINT route_span_pk PRIMARY KEY (route_name, span_name);


--
-- Name: span_events_information_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_events_information
    ADD CONSTRAINT span_events_information_pk PRIMARY KEY (event_id);


--
-- Name: span_incidents_information_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_incidents_information
    ADD CONSTRAINT span_incidents_information_pk PRIMARY KEY (incident_id);


--
-- Name: span_journey_average_duration_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_journey_average_duration
    ADD CONSTRAINT span_journey_average_duration_pkey PRIMARY KEY (span_name);


--
-- Name: span_journey_detection_analytics_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_journey_detection_analytics
    ADD CONSTRAINT span_journey_detection_analytics_pk PRIMARY KEY (span_journey_detection_analytics_id);


--
-- Name: span_journey_detection_cache_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_journey_detection_cache
    ADD CONSTRAINT span_journey_detection_cache_pk PRIMARY KEY (span_journey_detection_id);


--
-- Name: span_journey_detection_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_journey_detection
    ADD CONSTRAINT span_journey_detection_pk PRIMARY KEY (span_journey_detection_id);


--
-- Name: span_logical_group_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_logical_group
    ADD CONSTRAINT span_logical_group_pk PRIMARY KEY (span_name, logical_group_name);


--
-- Name: span_notes_information_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_notes_information
    ADD CONSTRAINT span_notes_information_pk PRIMARY KEY (note_id);


--
-- Name: span_osrm_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_osrm
    ADD CONSTRAINT span_osrm_pk PRIMARY KEY (span_name);


--
-- Name: span_span_name_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span
    ADD CONSTRAINT span_span_name_pk PRIMARY KEY (span_name);


--
-- Name: span_speed_thresholds_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_speed_thresholds
    ADD CONSTRAINT span_speed_thresholds_pk PRIMARY KEY (span_name);


--
-- Name: span_statistic_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span_statistic
    ADD CONSTRAINT span_statistic_pk PRIMARY KEY (span_name);


--
-- Name: start_end_detector_unique; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY span
    ADD CONSTRAINT start_end_detector_unique UNIQUE (start_detector_id, end_detector_id);


--
-- Name: statistics_device_id_pk; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY statistics_device
    ADD CONSTRAINT statistics_device_id_pk PRIMARY KEY (id);


--
-- Name: statistics_report_pkey; Type: CONSTRAINT; Schema: public; Owner: bluetruth; Tablespace: 
--

ALTER TABLE ONLY statistics_report
    ADD CONSTRAINT statistics_report_pkey PRIMARY KEY (report_id);


--
-- Name: completion_timestamp_cache_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX completion_timestamp_cache_index ON span_journey_detection_cache USING btree (completed_timestamp DESC NULLS LAST);


--
-- Name: completion_timestamp_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX completion_timestamp_index ON span_journey_detection USING btree (completed_timestamp DESC NULLS LAST);


--
-- Name: detection_timestamp_historic_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX detection_timestamp_historic_index ON device_detection_historic USING btree (detection_timestamp DESC);


--
-- Name: detection_timestamp_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX detection_timestamp_index ON device_detection USING btree (detection_timestamp DESC);


--
-- Name: detector_id_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE UNIQUE INDEX detector_id_index ON detector USING btree (detector_id);


--
-- Name: device_id_detector_id_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX device_id_detector_id_index ON device_detection USING btree (device_id NULLS FIRST, detector_id NULLS FIRST);


--
-- Name: device_id_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX device_id_index ON device_detection USING btree (device_id);


--
-- Name: first_seen_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX first_seen_index ON statistics_device USING btree (first_seen DESC);


--
-- Name: fki_detector_configuration_detector_id_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_detector_configuration_detector_id_fk ON detector_configuration USING btree (detector_id);


--
-- Name: fki_detector_id_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_detector_id_fk ON device_detection USING btree (detector_id);


--
-- Name: fki_detector_id_historic_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_detector_id_historic_fk ON device_detection_historic USING btree (detector_id);


--
-- Name: fki_detector_statistic_detector_id_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_detector_statistic_detector_id_fk ON detector_statistic USING btree (detector_id);


--
-- Name: fki_instation_user_timezone_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_instation_user_timezone_fk ON instation_user USING btree (timezone_name);


--
-- Name: fki_occupancy_detector_id; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_occupancy_detector_id ON occupancy USING btree (detector_id);


--
-- Name: fki_span_current_journey_time_span_name_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_current_journey_time_span_name_fk ON span_journey_average_duration USING btree (span_name);


--
-- Name: fki_span_end_detector_id; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_end_detector_id ON span USING btree (end_detector_id);


--
-- Name: fki_span_events_information_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_events_information_fk ON span_events_information USING btree (span_name);


--
-- Name: fki_span_journey_detection_cache_span_span_name_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_journey_detection_cache_span_span_name_fk ON span_journey_detection_cache USING btree (span_name);


--
-- Name: fki_span_journey_detection_id_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_journey_detection_id_fk ON span_journey_detection_analytics USING btree (span_journey_detection_id);


--
-- Name: fki_span_journey_detection_span_span_name_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_journey_detection_span_span_name_fk ON span_journey_detection USING btree (span_name);


--
-- Name: fki_span_logical_group_span_span_name_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_logical_group_span_span_name_fk ON span_logical_group USING btree (span_name);


--
-- Name: fki_span_notes_information_fk; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_notes_information_fk ON span_notes_information USING btree (span_name);


--
-- Name: fki_span_start_detector_id; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX fki_span_start_detector_id ON span USING btree (start_detector_id);


--
-- Name: last_seen_index; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX last_seen_index ON statistics_device USING btree (last_seen DESC);


--
-- Name: occupancy_reported_timestamp_idx; Type: INDEX; Schema: public; Owner: bluetruth; Tablespace: 
--

CREATE INDEX occupancy_reported_timestamp_idx ON occupancy USING btree (reported_timestamp DESC NULLS LAST);


--
-- Name: _RETURN; Type: RULE; Schema: public; Owner: bluetruth
--

CREATE RULE "_RETURN" AS
    ON SELECT TO instation_user_view DO INSTEAD  SELECT instation_user.full_name,
    instation_user.username,
    instation_user.email_address,
    (('['::text || array_to_string(array_agg(DISTINCT instation_user_role.role_name), '] ['::text)) || ']'::text) AS roles,
    (('['::text || array_to_string(array_agg(DISTINCT instation_user_logical_group.logical_group_name), '] ['::text)) || ']'::text) AS logical_groups,
    instation_user.activated
   FROM ((instation_user
     LEFT JOIN instation_user_role ON (((instation_user.username)::text = (instation_user_role.username)::text)))
     LEFT JOIN instation_user_logical_group ON (((instation_user.username)::text = (instation_user_logical_group.username)::text)))
  GROUP BY instation_user.full_name, instation_user.username;


--
-- Name: after_insert_on_detector; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER after_insert_on_detector AFTER INSERT ON detector FOR EACH ROW EXECUTE PROCEDURE after_insert_on_detector();


--
-- Name: after_insert_on_span; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER after_insert_on_span AFTER INSERT ON span FOR EACH ROW EXECUTE PROCEDURE after_insert_on_span();


--
-- Name: after_insert_on_span_journey_detection; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER after_insert_on_span_journey_detection AFTER INSERT ON span_journey_detection FOR EACH ROW EXECUTE PROCEDURE after_insert_on_span_journey_detection();


--
-- Name: after_insert_on_statistics_device; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER after_insert_on_statistics_device AFTER INSERT ON statistics_device FOR EACH ROW EXECUTE PROCEDURE after_insert_on_statistics_device();


--
-- Name: after_insert_update; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER after_insert_update AFTER INSERT OR UPDATE OF sl_2g_min, sl_2g_avg, sl_2g_max, sl_3g_min, sl_3g_avg, sl_3g_max, pi ON detector_status FOR EACH ROW EXECUTE PROCEDURE after_insert_update_on_detector_status();


--
-- Name: before _insert_on_span_journey_detection; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER "before _insert_on_span_journey_detection" BEFORE INSERT ON span_journey_detection FOR EACH ROW EXECUTE PROCEDURE before_insert_on_span_journey_detection();


--
-- Name: delete_duplicate_detector_logs; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER delete_duplicate_detector_logs BEFORE INSERT ON detector_log FOR EACH ROW EXECUTE PROCEDURE delete_duplicate_detector_logs();


--
-- Name: find_journey; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER find_journey BEFORE INSERT ON device_detection FOR EACH ROW EXECUTE PROCEDURE find_journey();


--
-- Name: find_journey_2_00; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER find_journey_2_00 BEFORE INSERT ON statistics_device FOR EACH ROW EXECUTE PROCEDURE find_journey_2_00();


--
-- Name: insert_historic_copy; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER insert_historic_copy BEFORE INSERT ON device_detection FOR EACH ROW EXECUTE PROCEDURE insert_historic_copy();


--
-- Name: insert_update_on_detector; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER insert_update_on_detector BEFORE INSERT OR UPDATE ON detector FOR EACH ROW EXECUTE PROCEDURE insert_update_on_detector();


--
-- Name: insert_update_on_span; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER insert_update_on_span BEFORE INSERT OR UPDATE ON span FOR EACH ROW EXECUTE PROCEDURE insert_update_on_span();


--
-- Name: refresh_span_journey_time; Type: TRIGGER; Schema: public; Owner: bluetruth
--

CREATE TRIGGER refresh_span_journey_time BEFORE UPDATE OF calculated_timestamp ON span_journey_average_duration FOR EACH ROW EXECUTE PROCEDURE refresh_span_journey_time_on_update();


--
-- Name: audit_trail_action_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY audit_trail
    ADD CONSTRAINT audit_trail_action_fk FOREIGN KEY (action_type) REFERENCES audit_trail_action(action_type) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: audit_trail_username_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY audit_trail
    ADD CONSTRAINT audit_trail_username_fk FOREIGN KEY (username) REFERENCES instation_user(username) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: branding_contact_details_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY branding_contact_details
    ADD CONSTRAINT branding_contact_details_fk FOREIGN KEY (brand) REFERENCES branding(brand) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: broadcast_message_logical_group_column_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY broadcast_message_logical_group
    ADD CONSTRAINT broadcast_message_logical_group_column_fk FOREIGN KEY (logical_group) REFERENCES logical_group(logical_group_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: broadcast_message_logical_group_message_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY broadcast_message_logical_group
    ADD CONSTRAINT broadcast_message_logical_group_message_id_fk FOREIGN KEY (message_id) REFERENCES broadcast_message(message_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_configuration_detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_configuration
    ADD CONSTRAINT detector_configuration_detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_confirmed_config_detector_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_confirmed_config
    ADD CONSTRAINT detector_confirmed_config_detector_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_confirmed_config_seed_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_confirmed_config
    ADD CONSTRAINT detector_confirmed_config_seed_id_fkey FOREIGN KEY (seed_id) REFERENCES detector_seed(id);


--
-- Name: detector_engineer_notes_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_engineer_notes
    ADD CONSTRAINT detector_engineer_notes_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_message
    ADD CONSTRAINT detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_log
    ADD CONSTRAINT detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY device_detection_historic
    ADD CONSTRAINT detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY device_detection
    ADD CONSTRAINT detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id);


--
-- Name: detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY occupancy
    ADD CONSTRAINT detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id);


--
-- Name: detector_keys_detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_keys
    ADD CONSTRAINT detector_keys_detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_logical_group_detector_id; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_logical_group
    ADD CONSTRAINT detector_logical_group_detector_id FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_logical_group_logical_group_name; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_logical_group
    ADD CONSTRAINT detector_logical_group_logical_group_name FOREIGN KEY (logical_group_name) REFERENCES logical_group(logical_group_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_seed_detector_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_seed
    ADD CONSTRAINT detector_seed_detector_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_statistic_detector_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_statistic
    ADD CONSTRAINT detector_statistic_detector_id_fk FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: detector_status_detector_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY detector_status
    ADD CONSTRAINT detector_status_detector_id_fkey FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: instation_user_brand_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY instation_user
    ADD CONSTRAINT instation_user_brand_fk FOREIGN KEY (brand) REFERENCES branding(brand) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: instation_user_logical_group_logical_group_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY instation_user_logical_group
    ADD CONSTRAINT instation_user_logical_group_logical_group_name_fk FOREIGN KEY (logical_group_name) REFERENCES logical_group(logical_group_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: instation_user_logical_group_username_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY instation_user_logical_group
    ADD CONSTRAINT instation_user_logical_group_username_fk FOREIGN KEY (username) REFERENCES instation_user(username) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: instation_user_timezone_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY instation_user
    ADD CONSTRAINT instation_user_timezone_fk FOREIGN KEY (timezone_name) REFERENCES instation_user_timezone(timezone_name) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: journey_time_service_user_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY journey_time_service_user
    ADD CONSTRAINT journey_time_service_user_username_fkey FOREIGN KEY (username) REFERENCES instation_user(username);


--
-- Name: occupancy_detector_id; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY occupancy
    ADD CONSTRAINT occupancy_detector_id FOREIGN KEY (detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: role_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY instation_user_role
    ADD CONSTRAINT role_fk FOREIGN KEY (role_name) REFERENCES instation_role(role_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: route_datex2_route_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY route_datex2
    ADD CONSTRAINT route_datex2_route_name_fk FOREIGN KEY (route_name) REFERENCES route(route_name);


--
-- Name: route_logical_group_logical_group_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY route_logical_group
    ADD CONSTRAINT route_logical_group_logical_group_name_fk FOREIGN KEY (logical_group_name) REFERENCES logical_group(logical_group_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: route_logical_group_route_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY route_logical_group
    ADD CONSTRAINT route_logical_group_route_name_fk FOREIGN KEY (route_name) REFERENCES route(route_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: route_span_route_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY route_span
    ADD CONSTRAINT route_span_route_name_fk FOREIGN KEY (route_name) REFERENCES route(route_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: route_span_span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY route_span
    ADD CONSTRAINT route_span_span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_current_journey_time_span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_journey_average_duration
    ADD CONSTRAINT span_current_journey_time_span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_end_detector_id; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span
    ADD CONSTRAINT span_end_detector_id FOREIGN KEY (end_detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_events_information_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_events_information
    ADD CONSTRAINT span_events_information_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_incidents_information_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_incidents_information
    ADD CONSTRAINT span_incidents_information_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_journey_detection_analytics_span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_journey_detection_analytics
    ADD CONSTRAINT span_journey_detection_analytics_span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_journey_detection_cache_span_span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_journey_detection_cache
    ADD CONSTRAINT span_journey_detection_cache_span_span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_journey_detection_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_journey_detection_analytics
    ADD CONSTRAINT span_journey_detection_id_fk FOREIGN KEY (span_journey_detection_id) REFERENCES span_journey_detection(span_journey_detection_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_journey_detection_span_span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_journey_detection
    ADD CONSTRAINT span_journey_detection_span_span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_logical_group_logical_group_name; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_logical_group
    ADD CONSTRAINT span_logical_group_logical_group_name FOREIGN KEY (logical_group_name) REFERENCES logical_group(logical_group_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_logical_group_span_span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_logical_group
    ADD CONSTRAINT span_logical_group_span_span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_name_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_osrm
    ADD CONSTRAINT span_name_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_notes_information_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_notes_information
    ADD CONSTRAINT span_notes_information_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_speed_thresholds_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_speed_thresholds
    ADD CONSTRAINT span_speed_thresholds_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_start_detector_id; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span
    ADD CONSTRAINT span_start_detector_id FOREIGN KEY (start_detector_id) REFERENCES detector(detector_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: span_statistic_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY span_statistic
    ADD CONSTRAINT span_statistic_fk FOREIGN KEY (span_name) REFERENCES span(span_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: statistics_device_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY statistics_device
    ADD CONSTRAINT statistics_device_report_id_fkey FOREIGN KEY (report_id) REFERENCES statistics_report(report_id);


--
-- Name: username_fk; Type: FK CONSTRAINT; Schema: public; Owner: bluetruth
--

ALTER TABLE ONLY instation_user_role
    ADD CONSTRAINT username_fk FOREIGN KEY (username) REFERENCES instation_user(username) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

