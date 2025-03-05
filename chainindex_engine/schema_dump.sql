--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.15 (Ubuntu 14.15-0ubuntu0.22.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: finance; Type: SCHEMA; Schema: -; Owner: root
--

CREATE SCHEMA finance;


ALTER SCHEMA finance OWNER TO root;

--
-- Name: SCHEMA finance; Type: COMMENT; Schema: -; Owner: root
--

COMMENT ON SCHEMA finance IS 'steampipe plugin: hub.steampipe.io/plugins/turbot/finance@latest';


--
-- Name: hackernews; Type: SCHEMA; Schema: -; Owner: root
--

CREATE SCHEMA hackernews;


ALTER SCHEMA hackernews OWNER TO root;

--
-- Name: SCHEMA hackernews; Type: COMMENT; Schema: -; Owner: root
--

COMMENT ON SCHEMA hackernews IS 'steampipe plugin: hub.steampipe.io/plugins/turbot/hackernews@latest';


--
-- Name: steampipe_command; Type: SCHEMA; Schema: -; Owner: root
--

CREATE SCHEMA steampipe_command;


ALTER SCHEMA steampipe_command OWNER TO root;

--
-- Name: steampipe_internal; Type: SCHEMA; Schema: -; Owner: root
--

CREATE SCHEMA steampipe_internal;


ALTER SCHEMA steampipe_internal OWNER TO root;

--
-- Name: taptools; Type: SCHEMA; Schema: -; Owner: root
--

CREATE SCHEMA taptools;


ALTER SCHEMA taptools OWNER TO root;

--
-- Name: SCHEMA taptools; Type: COMMENT; Schema: -; Owner: root
--

COMMENT ON SCHEMA taptools IS 'steampipe plugin: hub.steampipe.io/plugins/turbot/taptools@latest';


--
-- Name: twitter; Type: SCHEMA; Schema: -; Owner: root
--

CREATE SCHEMA twitter;


ALTER SCHEMA twitter OWNER TO root;

--
-- Name: SCHEMA twitter; Type: COMMENT; Schema: -; Owner: root
--

COMMENT ON SCHEMA twitter IS 'steampipe plugin: hub.steampipe.io/plugins/turbot/twitter@latest';


--
-- Name: ltree; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA public;


--
-- Name: EXTENSION ltree; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION ltree IS 'data type for hierarchical tree-like structures';


--
-- Name: steampipe_postgres_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS steampipe_postgres_fdw WITH SCHEMA public;


--
-- Name: EXTENSION steampipe_postgres_fdw; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION steampipe_postgres_fdw IS 'Steampipe Foreign Data Wrapper';


--
-- Name: tablefunc; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS tablefunc WITH SCHEMA public;


--
-- Name: EXTENSION tablefunc; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION tablefunc IS 'functions that manipulate whole tables, including crosstab';


--
-- Name: clone_foreign_schema(text, text, text); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.clone_foreign_schema(source_schema text, dest_schema text, plugin_name text) RETURNS text
    LANGUAGE plpgsql
    AS $_$

DECLARE	
    src_oid          oid;
    object           text;
    dest_table       text;
    table_sql        text;
    columns_sql      text;
    type_            text;
    column_          text;
    underlying_type  text;
    res              text;
BEGIN

    -- Check that source_schema exists
    SELECT oid INTO src_oid
    FROM pg_namespace
    WHERE nspname = source_schema;
    IF NOT FOUND
    THEN
        RAISE EXCEPTION 'source schema % does not exist!', source_schema;
        RETURN '';
    END IF;

    -- Create schema
    EXECUTE 'DROP SCHEMA IF EXISTS "' ||  dest_schema || '" CASCADE';
    EXECUTE 'CREATE SCHEMA "' || dest_schema || '"';
    EXECUTE 'GRANT USAGE ON SCHEMA "' || dest_schema || '" TO steampipe_users';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA "' || dest_schema || '" GRANT SELECT ON TABLES TO steampipe_users';

    -- Create tables
    FOR object IN
        SELECT TABLE_NAME::text
        FROM information_schema.tables
        WHERE table_schema = source_schema
          AND table_type = 'FOREIGN'
    LOOP
        columns_sql := '';

        FOR column_, type_ IN
            SELECT c.column_name::text, 
                   CASE 
                       WHEN c.data_type = 'USER-DEFINED' THEN t.typname
                       ELSE c.data_type
                   END as data_type
            FROM information_schema.COLUMNS c
            LEFT JOIN pg_catalog.pg_type t ON c.udt_name = t.typname
            WHERE c.table_schema = source_schema
              AND c.TABLE_NAME = object
        LOOP
            IF columns_sql <> ''
            THEN
                columns_sql = columns_sql || ',';
            END IF;
            columns_sql = columns_sql || quote_ident(column_) || ' ' || type_;
        END LOOP;

        dest_table := '"' || dest_schema || '".' || quote_ident(object);
        table_sql :='CREATE FOREIGN TABLE ' || dest_table || ' (' || columns_sql || ') SERVER steampipe OPTIONS (table '|| $$'$$ || quote_ident(object) || $$'$$ || ') ';
        EXECUTE table_sql;

        SELECT CONCAT(res, table_sql, ';') into res;
    END LOOP;
    RETURN res;
END

$_$;


ALTER FUNCTION public.clone_foreign_schema(source_schema text, dest_schema text, plugin_name text) OWNER TO root;

--
-- Name: clone_table_comments(text, text); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.clone_table_comments(source_schema text, dest_schema text) RETURNS text
    LANGUAGE plpgsql
    AS $_$

DECLARE
    src_oid         oid;
    dest_oid        oid;
    t               text;
    ret             text;
    query           text;
    table_desc      text;
    column_desc     text;
    column_number   int;
    c               text;
BEGIN

    -- Check that source_schema and dest_schema exist
    SELECT oid INTO src_oid
    FROM pg_namespace
    WHERE nspname = quote_ident(source_schema);
    IF NOT FOUND
    THEN
        RAISE NOTICE 'source schema % does not exist!', source_schema;
        RETURN 'source schema does not exist!';
    END IF;

    SELECT oid INTO dest_oid
    FROM pg_namespace
    WHERE nspname = quote_ident(dest_schema);
    IF NOT FOUND
    THEN
        RAISE NOTICE 'dest schema % does not exist!', dest_schema;
        RETURN 'dest schema does not exist!';
    END IF;


    -- Copy comments
    FOR t IN
        SELECT table_name::text
        FROM information_schema.tables
            WHERE table_schema = quote_ident(source_schema)
            AND table_type = 'FOREIGN'
    LOOP
        SELECT OBJ_DESCRIPTION((quote_ident(source_schema) || '.' || quote_ident(t))::REGCLASS) INTO table_desc;
        query = 'COMMENT ON FOREIGN TABLE ' || quote_ident(dest_schema) ||  '.' || quote_ident(t) || ' IS $steampipe_escape$' || table_desc || '$steampipe_escape$';
       SELECT CONCAT(ret, query || '\n') INTO ret;
        EXECUTE query;

        FOR  c,column_number IN
            SELECT column_name, ordinal_position
            FROM information_schema.COLUMNS
                WHERE table_schema = quote_ident(source_schema)
                AND table_name = quote_ident(t)
        LOOP
            SELECT PG_CATALOG.COL_DESCRIPTION((quote_ident(source_schema) || '.' || quote_ident(t))::REGCLASS::OID, column_number) INTO column_desc;
            query = 'COMMENT ON COLUMN ' || quote_ident(dest_schema) ||  '.' || quote_ident(t) ||  '.' || quote_ident(c) || ' IS $steampipe_escape$' || column_desc || '$steampipe_escape$';
--            SELECT CONCAT(ret, query || '\n') INTO ret;
            EXECUTE query;
        END LOOP;
    END LOOP;

    RETURN ret;
END

$_$;


ALTER FUNCTION public.clone_table_comments(source_schema text, dest_schema text) OWNER TO root;

--
-- Name: glob(text); Type: FUNCTION; Schema: steampipe_internal; Owner: root
--

CREATE FUNCTION steampipe_internal.glob(input_glob text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	output_pattern text;
begin
	output_pattern = replace(input_glob, '*', '%');
	output_pattern = replace(output_pattern, '?', '_');
	return output_pattern;
end;
$$;


ALTER FUNCTION steampipe_internal.glob(input_glob text) OWNER TO root;

--
-- Name: meta_cache(text); Type: FUNCTION; Schema: steampipe_internal; Owner: root
--

CREATE FUNCTION steampipe_internal.meta_cache(command text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
begin
	IF command = 'on' THEN
		INSERT INTO steampipe_internal.steampipe_settings("name","value") VALUES ('cache','true');
	ELSIF command = 'off' THEN
		INSERT INTO steampipe_internal.steampipe_settings("name","value") VALUES ('cache','false');
	ELSIF command = 'clear' THEN
		INSERT INTO steampipe_internal.steampipe_settings("name","value") VALUES ('cache_clear_time','');
	ELSE
		RAISE EXCEPTION 'Unknown value % for set_cache - valid values are on, off and clear.', $1;
	END IF;
end;
$_$;


ALTER FUNCTION steampipe_internal.meta_cache(command text) OWNER TO root;

--
-- Name: meta_cache_ttl(integer); Type: FUNCTION; Schema: steampipe_internal; Owner: root
--

CREATE FUNCTION steampipe_internal.meta_cache_ttl(duration integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
	INSERT INTO steampipe_internal.steampipe_settings("name","value") VALUES ('cache_ttl',duration);
end;
$$;


ALTER FUNCTION steampipe_internal.meta_cache_ttl(duration integer) OWNER TO root;

--
-- Name: meta_connection_cache_clear(text); Type: FUNCTION; Schema: steampipe_internal; Owner: root
--

CREATE FUNCTION steampipe_internal.meta_connection_cache_clear(connection text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
		INSERT INTO steampipe_internal.steampipe_settings("name","value") VALUES ('connection_cache_clear',connection);
end;
$$;


ALTER FUNCTION steampipe_internal.meta_connection_cache_clear(connection text) OWNER TO root;

--
-- Name: steampipe; Type: SERVER; Schema: -; Owner: root
--

CREATE SERVER steampipe FOREIGN DATA WRAPPER steampipe_postgres_fdw;


ALTER SERVER steampipe OWNER TO root;

SET default_tablespace = '';

--
-- Name: finance_quote; Type: FOREIGN TABLE; Schema: finance; Owner: root
--

CREATE FOREIGN TABLE finance.finance_quote (
    symbol text,
    short_name text,
    regular_market_price double precision,
    regular_market_time timestamp with time zone,
    ask double precision,
    ask_size double precision,
    average_daily_volume_10_day bigint,
    average_daily_volume_3_month bigint,
    bid double precision,
    bid_size double precision,
    currency_id text,
    exchange_id text,
    exchange_timezone_name text,
    exchange_timezone_short_name text,
    fifty_day_average double precision,
    fifty_day_average_change double precision,
    fifty_day_average_change_percent double precision,
    fifty_two_week_high double precision,
    fifty_two_week_high_change double precision,
    fifty_two_week_high_change_percent double precision,
    fifty_two_week_low double precision,
    fifty_two_week_low_change double precision,
    fifty_two_week_low_change_percent double precision,
    full_exchange_name text,
    gmt_offset_milliseconds bigint,
    is_tradeable boolean,
    market_id text,
    market_state text,
    post_market_change double precision,
    post_market_change_percent double precision,
    post_market_price double precision,
    post_market_time timestamp with time zone,
    pre_market_change double precision,
    pre_market_change_percent double precision,
    pre_market_price double precision,
    pre_market_time timestamp with time zone,
    quote_delay bigint,
    quote_source text,
    quote_type text,
    regular_market_change double precision,
    regular_market_change_percent double precision,
    regular_market_day_high double precision,
    regular_market_day_low double precision,
    regular_market_open double precision,
    regular_market_previous_close double precision,
    regular_market_volume bigint,
    source_interval bigint,
    two_hundred_day_average double precision,
    two_hundred_day_average_change double precision,
    two_hundred_day_average_change_percent double precision,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'finance_quote'
);


ALTER FOREIGN TABLE finance.finance_quote OWNER TO root;

--
-- Name: FOREIGN TABLE finance_quote; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON FOREIGN TABLE finance.finance_quote IS 'Most recent available quote for the given symbol.';


--
-- Name: COLUMN finance_quote.symbol; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.symbol IS 'Symbol to quote.';


--
-- Name: COLUMN finance_quote.short_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.short_name IS 'Short descriptive name for the entity.';


--
-- Name: COLUMN finance_quote.regular_market_price; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_price IS 'Price in the regular market.';


--
-- Name: COLUMN finance_quote.regular_market_time; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_time IS 'Time when the regular market data was updated.';


--
-- Name: COLUMN finance_quote.ask; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.ask IS 'Ask price. ';


--
-- Name: COLUMN finance_quote.ask_size; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.ask_size IS 'Ask size.';


--
-- Name: COLUMN finance_quote.average_daily_volume_10_day; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.average_daily_volume_10_day IS 'Average daily volume - last 10 days.';


--
-- Name: COLUMN finance_quote.average_daily_volume_3_month; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.average_daily_volume_3_month IS 'Average daily volume - last 3 months.';


--
-- Name: COLUMN finance_quote.bid; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.bid IS 'Bid price.';


--
-- Name: COLUMN finance_quote.bid_size; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.bid_size IS 'Bid size.';


--
-- Name: COLUMN finance_quote.currency_id; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.currency_id IS 'Currency ID, e.g. AUD, USD.';


--
-- Name: COLUMN finance_quote.exchange_id; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.exchange_id IS 'Exchange ID, e.g. NYQ, CCC.';


--
-- Name: COLUMN finance_quote.exchange_timezone_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.exchange_timezone_name IS 'Timezone at the exchange.';


--
-- Name: COLUMN finance_quote.exchange_timezone_short_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.exchange_timezone_short_name IS 'Timezone short name at the exchange.';


--
-- Name: COLUMN finance_quote.fifty_day_average; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_day_average IS '50 day average price.';


--
-- Name: COLUMN finance_quote.fifty_day_average_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_day_average_change IS '50 day average change.';


--
-- Name: COLUMN finance_quote.fifty_day_average_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_day_average_change_percent IS '50 day average change percentage.';


--
-- Name: COLUMN finance_quote.fifty_two_week_high; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_two_week_high IS '52 week high.';


--
-- Name: COLUMN finance_quote.fifty_two_week_high_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_two_week_high_change IS '52 week high change.';


--
-- Name: COLUMN finance_quote.fifty_two_week_high_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_two_week_high_change_percent IS '52 week high change percentage.';


--
-- Name: COLUMN finance_quote.fifty_two_week_low; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_two_week_low IS '52 week low.';


--
-- Name: COLUMN finance_quote.fifty_two_week_low_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_two_week_low_change IS '52 week low change.';


--
-- Name: COLUMN finance_quote.fifty_two_week_low_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.fifty_two_week_low_change_percent IS '52 week low change percent.';


--
-- Name: COLUMN finance_quote.full_exchange_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.full_exchange_name IS 'Full exchange name.';


--
-- Name: COLUMN finance_quote.gmt_offset_milliseconds; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.gmt_offset_milliseconds IS 'GMT offset in milliseconds.';


--
-- Name: COLUMN finance_quote.is_tradeable; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.is_tradeable IS 'True if the symbol is tradeable.';


--
-- Name: COLUMN finance_quote.market_id; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.market_id IS 'Market identifier, e.g. us_market.';


--
-- Name: COLUMN finance_quote.market_state; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.market_state IS 'Current state of the market, e.g. REGULAR, CLOSED.';


--
-- Name: COLUMN finance_quote.post_market_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.post_market_change IS 'Post market price change.';


--
-- Name: COLUMN finance_quote.post_market_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.post_market_change_percent IS 'Post market price change percentage.';


--
-- Name: COLUMN finance_quote.post_market_price; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.post_market_price IS 'Post market price.';


--
-- Name: COLUMN finance_quote.post_market_time; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.post_market_time IS 'Timestamp for post market data.';


--
-- Name: COLUMN finance_quote.pre_market_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.pre_market_change IS 'Pre market price change.';


--
-- Name: COLUMN finance_quote.pre_market_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.pre_market_change_percent IS 'Pre market price change percentage.';


--
-- Name: COLUMN finance_quote.pre_market_price; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.pre_market_price IS 'Pre market price.';


--
-- Name: COLUMN finance_quote.pre_market_time; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.pre_market_time IS 'Timestamp for pre market data.';


--
-- Name: COLUMN finance_quote.quote_delay; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.quote_delay IS 'Quote delay in minutes.';


--
-- Name: COLUMN finance_quote.quote_source; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.quote_source IS 'Quote source.';


--
-- Name: COLUMN finance_quote.quote_type; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.quote_type IS 'Quote type, e.g. EQUITY, CRYPTOCURRENCY.';


--
-- Name: COLUMN finance_quote.regular_market_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_change IS 'Change in price since the regular market open.';


--
-- Name: COLUMN finance_quote.regular_market_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_change_percent IS 'Change percentage during the regular market session.';


--
-- Name: COLUMN finance_quote.regular_market_day_high; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_day_high IS 'High price for the regular market day.';


--
-- Name: COLUMN finance_quote.regular_market_day_low; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_day_low IS 'Low price for the regular market day.';


--
-- Name: COLUMN finance_quote.regular_market_open; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_open IS 'Opening price for the regular market.';


--
-- Name: COLUMN finance_quote.regular_market_previous_close; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_previous_close IS 'Close price of the previous regular market session.';


--
-- Name: COLUMN finance_quote.regular_market_volume; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.regular_market_volume IS 'Trading volume for the regular market session.';


--
-- Name: COLUMN finance_quote.source_interval; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.source_interval IS 'Source interval in minutes.';


--
-- Name: COLUMN finance_quote.two_hundred_day_average; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.two_hundred_day_average IS '200 day average price.';


--
-- Name: COLUMN finance_quote.two_hundred_day_average_change; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.two_hundred_day_average_change IS '200 day average price change.';


--
-- Name: COLUMN finance_quote.two_hundred_day_average_change_percent; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.two_hundred_day_average_change_percent IS '200 day average price change percentage.';


--
-- Name: COLUMN finance_quote.sp_connection_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN finance_quote.sp_ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN finance_quote._ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote._ctx IS 'Steampipe context in JSON form.';


--
-- Name: finance_quote_daily; Type: FOREIGN TABLE; Schema: finance; Owner: root
--

CREATE FOREIGN TABLE finance.finance_quote_daily (
    symbol text,
    adjusted_close double precision,
    close double precision,
    high double precision,
    low double precision,
    open double precision,
    "timestamp" timestamp with time zone,
    volume bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'finance_quote_daily'
);


ALTER FOREIGN TABLE finance.finance_quote_daily OWNER TO root;

--
-- Name: FOREIGN TABLE finance_quote_daily; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON FOREIGN TABLE finance.finance_quote_daily IS 'Daily historical quotes for a given symbol.';


--
-- Name: COLUMN finance_quote_daily.symbol; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.symbol IS 'Symbol to quote.';


--
-- Name: COLUMN finance_quote_daily.adjusted_close; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.adjusted_close IS 'Adjusted close price after accounting for any corporate actions.';


--
-- Name: COLUMN finance_quote_daily.close; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.close IS 'Last price during the regular trading session.';


--
-- Name: COLUMN finance_quote_daily.high; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.high IS 'Highest price during the trading session.';


--
-- Name: COLUMN finance_quote_daily.low; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.low IS 'Lowest price during the trading session.';


--
-- Name: COLUMN finance_quote_daily.open; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.open IS 'Opening price during the trading session.';


--
-- Name: COLUMN finance_quote_daily."timestamp"; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily."timestamp" IS 'Timestamp of the record.';


--
-- Name: COLUMN finance_quote_daily.volume; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.volume IS 'Total trading volume (units bought and sold) during the period.';


--
-- Name: COLUMN finance_quote_daily.sp_connection_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN finance_quote_daily.sp_ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN finance_quote_daily._ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_daily._ctx IS 'Steampipe context in JSON form.';


--
-- Name: finance_quote_hourly; Type: FOREIGN TABLE; Schema: finance; Owner: root
--

CREATE FOREIGN TABLE finance.finance_quote_hourly (
    symbol text,
    adjusted_close double precision,
    close double precision,
    high double precision,
    low double precision,
    open double precision,
    "timestamp" timestamp with time zone,
    volume bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'finance_quote_hourly'
);


ALTER FOREIGN TABLE finance.finance_quote_hourly OWNER TO root;

--
-- Name: FOREIGN TABLE finance_quote_hourly; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON FOREIGN TABLE finance.finance_quote_hourly IS 'Hourly historical quotes for a given symbol.';


--
-- Name: COLUMN finance_quote_hourly.symbol; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.symbol IS 'Symbol to quote.';


--
-- Name: COLUMN finance_quote_hourly.adjusted_close; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.adjusted_close IS 'Adjusted close price after accounting for any corporate actions.';


--
-- Name: COLUMN finance_quote_hourly.close; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.close IS 'Last price during the regular trading session.';


--
-- Name: COLUMN finance_quote_hourly.high; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.high IS 'Highest price during the trading session.';


--
-- Name: COLUMN finance_quote_hourly.low; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.low IS 'Lowest price during the trading session.';


--
-- Name: COLUMN finance_quote_hourly.open; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.open IS 'Opening price during the trading session.';


--
-- Name: COLUMN finance_quote_hourly."timestamp"; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly."timestamp" IS 'Timestamp of the record.';


--
-- Name: COLUMN finance_quote_hourly.volume; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.volume IS 'Total trading volume (units bought and sold) during the period.';


--
-- Name: COLUMN finance_quote_hourly.sp_connection_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN finance_quote_hourly.sp_ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN finance_quote_hourly._ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_quote_hourly._ctx IS 'Steampipe context in JSON form.';


--
-- Name: finance_us_sec_filer; Type: FOREIGN TABLE; Schema: finance; Owner: root
--

CREATE FOREIGN TABLE finance.finance_us_sec_filer (
    symbol text,
    cik text,
    name text,
    sic text,
    sic_description text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'finance_us_sec_filer'
);


ALTER FOREIGN TABLE finance.finance_us_sec_filer OWNER TO root;

--
-- Name: FOREIGN TABLE finance_us_sec_filer; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON FOREIGN TABLE finance.finance_us_sec_filer IS 'Lookup company filer details from the US SEC Edgar database.';


--
-- Name: COLUMN finance_us_sec_filer.symbol; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.symbol IS 'Symbol for the filer.';


--
-- Name: COLUMN finance_us_sec_filer.cik; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.cik IS 'CIK (Central Index Key) of the filer.';


--
-- Name: COLUMN finance_us_sec_filer.name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.name IS 'Name of the filer.';


--
-- Name: COLUMN finance_us_sec_filer.sic; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.sic IS 'SIC (Standard Industrial Classification) of the filer.';


--
-- Name: COLUMN finance_us_sec_filer.sic_description; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.sic_description IS 'Description of the SIC (Standard Industrial Classification) of the filer.';


--
-- Name: COLUMN finance_us_sec_filer.sp_connection_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN finance_us_sec_filer.sp_ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN finance_us_sec_filer._ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_filer._ctx IS 'Steampipe context in JSON form.';


--
-- Name: finance_us_sec_public_company; Type: FOREIGN TABLE; Schema: finance; Owner: root
--

CREATE FOREIGN TABLE finance.finance_us_sec_public_company (
    name text,
    symbol text,
    cik text,
    currency text,
    is_enabled boolean,
    date timestamp with time zone,
    exchange text,
    exchange_name text,
    exchange_segment text,
    exchange_segment_name text,
    exchange_suffix text,
    figi text,
    iex_id text,
    lei text,
    region text,
    type text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'finance_us_sec_public_company'
);


ALTER FOREIGN TABLE finance.finance_us_sec_public_company OWNER TO root;

--
-- Name: FOREIGN TABLE finance_us_sec_public_company; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON FOREIGN TABLE finance.finance_us_sec_public_company IS 'US public companies from the SEC Edgar database.';


--
-- Name: COLUMN finance_us_sec_public_company.name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.name IS 'Name of the company.';


--
-- Name: COLUMN finance_us_sec_public_company.symbol; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.symbol IS 'Symbol of the company.';


--
-- Name: COLUMN finance_us_sec_public_company.cik; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.cik IS 'Central Index Key (CIK), if available for the company. The CIK is used to identify entities that are regulated by the Securities and Exchange Commission (SEC).';


--
-- Name: COLUMN finance_us_sec_public_company.currency; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.currency IS 'Currency the symbol is traded in using.';


--
-- Name: COLUMN finance_us_sec_public_company.is_enabled; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.is_enabled IS 'True if the symbol is enabled for trading on IEX.';


--
-- Name: COLUMN finance_us_sec_public_company.date; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.date IS 'Date the symbol reference data was generated.';


--
-- Name: COLUMN finance_us_sec_public_company.exchange; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.exchange IS 'Exchange symbol.';


--
-- Name: COLUMN finance_us_sec_public_company.exchange_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.exchange_name IS 'Exchange name.';


--
-- Name: COLUMN finance_us_sec_public_company.exchange_segment; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.exchange_segment IS 'Exchange segment.';


--
-- Name: COLUMN finance_us_sec_public_company.exchange_segment_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.exchange_segment_name IS 'Exchange segment name.';


--
-- Name: COLUMN finance_us_sec_public_company.exchange_suffix; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.exchange_suffix IS 'Exchange segment suffix.';


--
-- Name: COLUMN finance_us_sec_public_company.figi; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.figi IS 'OpenFIGI id for the security, if available.';


--
-- Name: COLUMN finance_us_sec_public_company.iex_id; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.iex_id IS 'Unique ID applied by IEX to track securities through symbol changes.';


--
-- Name: COLUMN finance_us_sec_public_company.lei; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.lei IS 'Legal Entity Identifier (LEI) for the security, if available.';


--
-- Name: COLUMN finance_us_sec_public_company.region; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.region IS 'Country code for the symbol.';


--
-- Name: COLUMN finance_us_sec_public_company.type; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.type IS 'common issue typepossible values are: ad - ADR, cs - Common Stock, cef - Closed End Fund, et - ETF, oef - Open Ended Fund, ps - Preferred Stock, rt - Right, struct - Structured Product, ut - Unit, wi - When Issued, wt - Warrant, empty - Other.';


--
-- Name: COLUMN finance_us_sec_public_company.sp_connection_name; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN finance_us_sec_public_company.sp_ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN finance_us_sec_public_company._ctx; Type: COMMENT; Schema: finance; Owner: root
--

COMMENT ON COLUMN finance.finance_us_sec_public_company._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_ask_hn; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_ask_hn (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_ask_hn'
);


ALTER FOREIGN TABLE hackernews.hackernews_ask_hn OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_ask_hn; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_ask_hn IS 'Latest 200 Ask HN stories.';


--
-- Name: COLUMN hackernews_ask_hn.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_ask_hn.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_ask_hn."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_ask_hn.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_ask_hn.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_ask_hn.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_ask_hn.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_ask_hn.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_ask_hn.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_ask_hn.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_ask_hn.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_ask_hn.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_ask_hn.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_ask_hn.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_ask_hn.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_ask_hn.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_ask_hn.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_ask_hn._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_ask_hn._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_best; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_best (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_best'
);


ALTER FOREIGN TABLE hackernews.hackernews_best OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_best; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_best IS 'Best 500 stories.';


--
-- Name: COLUMN hackernews_best.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_best.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_best."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_best.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_best.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_best.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_best.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_best.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_best.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_best.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_best.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_best.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_best.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_best.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_best.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_best.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_best.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_best._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_best._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_item; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_item (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_item'
);


ALTER FOREIGN TABLE hackernews.hackernews_item OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_item; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_item IS 'Stories, comments, jobs, Ask HNs and even polls are just items. This table includes the most recent items posted to Hacker News.';


--
-- Name: COLUMN hackernews_item.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_item.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_item."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_item.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_item.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_item.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_item.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_item.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_item.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_item.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_item.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_item.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_item.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_item.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_item.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_item.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_item.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_item._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_item._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_job; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_job (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_job'
);


ALTER FOREIGN TABLE hackernews.hackernews_job OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_job; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_job IS 'Latest 200 Job stories.';


--
-- Name: COLUMN hackernews_job.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_job.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_job."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_job.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_job.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_job.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_job.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_job.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_job.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_job.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_job.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_job.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_job.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_job.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_job.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_job.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_job.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_job._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_job._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_new; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_new (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_new'
);


ALTER FOREIGN TABLE hackernews.hackernews_new OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_new; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_new IS 'Newest 500 stories.';


--
-- Name: COLUMN hackernews_new.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_new.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_new."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_new.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_new.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_new.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_new.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_new.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_new.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_new.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_new.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_new.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_new.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_new.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_new.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_new.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_new.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_new._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_new._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_show_hn; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_show_hn (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_show_hn'
);


ALTER FOREIGN TABLE hackernews.hackernews_show_hn OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_show_hn; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_show_hn IS 'Latest 200 Show HN stories.';


--
-- Name: COLUMN hackernews_show_hn.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_show_hn.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_show_hn."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_show_hn.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_show_hn.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_show_hn.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_show_hn.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_show_hn.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_show_hn.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_show_hn.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_show_hn.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_show_hn.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_show_hn.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_show_hn.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_show_hn.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_show_hn.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_show_hn.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_show_hn._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_show_hn._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_top; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_top (
    id bigint,
    title text,
    "time" timestamp with time zone,
    by text,
    score bigint,
    dead boolean,
    deleted boolean,
    descendants bigint,
    kids jsonb,
    parent bigint,
    parts jsonb,
    poll bigint,
    text text,
    type text,
    url text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_top'
);


ALTER FOREIGN TABLE hackernews.hackernews_top OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_top; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_top IS 'Top 500 stories.';


--
-- Name: COLUMN hackernews_top.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.id IS 'The item''s unique id.';


--
-- Name: COLUMN hackernews_top.title; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.title IS 'The title of the story, poll or job. HTML.';


--
-- Name: COLUMN hackernews_top."time"; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top."time" IS 'Timestamp when the item was created.';


--
-- Name: COLUMN hackernews_top.by; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.by IS 'The username of the item''s author.';


--
-- Name: COLUMN hackernews_top.score; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.score IS 'The story''s score, or the votes for a pollopt.';


--
-- Name: COLUMN hackernews_top.dead; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.dead IS 'True if the item is dead.';


--
-- Name: COLUMN hackernews_top.deleted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.deleted IS 'True if the item is deleted.';


--
-- Name: COLUMN hackernews_top.descendants; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.descendants IS 'In the case of stories or polls, the total comment count.';


--
-- Name: COLUMN hackernews_top.kids; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.kids IS 'The ids of the item''s comments, in ranked display order.';


--
-- Name: COLUMN hackernews_top.parent; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.parent IS 'The comment''s parent: either another comment or the relevant story.';


--
-- Name: COLUMN hackernews_top.parts; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.parts IS 'A list of related pollopts, in display order.';


--
-- Name: COLUMN hackernews_top.poll; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.poll IS 'The pollopt''s associated poll.';


--
-- Name: COLUMN hackernews_top.text; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.text IS 'The comment, story or poll text. HTML.';


--
-- Name: COLUMN hackernews_top.type; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.type IS 'The type of item. One of "job", "story", "comment", "poll", or "pollopt".';


--
-- Name: COLUMN hackernews_top.url; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.url IS 'The URL of the story.';


--
-- Name: COLUMN hackernews_top.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_top.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_top._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_top._ctx IS 'Steampipe context in JSON form.';


--
-- Name: hackernews_user; Type: FOREIGN TABLE; Schema: hackernews; Owner: root
--

CREATE FOREIGN TABLE hackernews.hackernews_user (
    id text,
    created text,
    karma bigint,
    about text,
    submitted jsonb,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'hackernews_user'
);


ALTER FOREIGN TABLE hackernews.hackernews_user OWNER TO root;

--
-- Name: FOREIGN TABLE hackernews_user; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON FOREIGN TABLE hackernews.hackernews_user IS 'Information about Hacker News registered users who have public activity.';


--
-- Name: COLUMN hackernews_user.id; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.id IS 'The user''s unique username. Case-sensitive. Required.';


--
-- Name: COLUMN hackernews_user.created; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.created IS 'Creation timestamp of the user.';


--
-- Name: COLUMN hackernews_user.karma; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.karma IS 'The user''s karma.';


--
-- Name: COLUMN hackernews_user.about; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.about IS 'The user''s optional self-description. HTML.';


--
-- Name: COLUMN hackernews_user.submitted; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.submitted IS 'List of the user''s stories, polls and comments.';


--
-- Name: COLUMN hackernews_user.sp_connection_name; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN hackernews_user.sp_ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN hackernews_user._ctx; Type: COMMENT; Schema: hackernews; Owner: root
--

COMMENT ON COLUMN hackernews.hackernews_user._ctx IS 'Steampipe context in JSON form.';


--
-- Name: cache; Type: FOREIGN TABLE; Schema: steampipe_command; Owner: root
--

CREATE FOREIGN TABLE steampipe_command.cache (
    operation text
)
SERVER steampipe
OPTIONS (
    "table" 'cache'
);


ALTER FOREIGN TABLE steampipe_command.cache OWNER TO root;

--
-- Name: scan_metadata; Type: FOREIGN TABLE; Schema: steampipe_command; Owner: root
--

CREATE FOREIGN TABLE steampipe_command.scan_metadata (
    id bigint,
    "table" text,
    cache_hit boolean,
    rows_fetched bigint,
    hydrate_calls bigint,
    start_time timestamp with time zone,
    duration double precision,
    columns jsonb,
    "limit" bigint,
    quals text
)
SERVER steampipe
OPTIONS (
    "table" 'scan_metadata'
);


ALTER FOREIGN TABLE steampipe_command.scan_metadata OWNER TO root;

SET default_table_access_method = heap;

--
-- Name: steampipe_connection; Type: TABLE; Schema: steampipe_internal; Owner: root
--

CREATE TABLE steampipe_internal.steampipe_connection (
    name text NOT NULL,
    state text,
    type text,
    connections text[],
    import_schema text,
    error text,
    plugin text,
    plugin_instance text,
    schema_mode text,
    schema_hash text,
    comments_set boolean DEFAULT false,
    connection_mod_time timestamp with time zone,
    plugin_mod_time timestamp with time zone,
    file_name text,
    start_line_number integer,
    end_line_number integer
);


ALTER TABLE steampipe_internal.steampipe_connection OWNER TO root;

--
-- Name: steampipe_connection_state; Type: TABLE; Schema: steampipe_internal; Owner: root
--

CREATE TABLE steampipe_internal.steampipe_connection_state (
    name text NOT NULL,
    state text,
    type text,
    connections text[],
    import_schema text,
    error text,
    plugin text,
    plugin_instance text,
    schema_mode text,
    schema_hash text,
    comments_set boolean DEFAULT false,
    connection_mod_time timestamp with time zone,
    plugin_mod_time timestamp with time zone,
    file_name text,
    start_line_number integer,
    end_line_number integer
);


ALTER TABLE steampipe_internal.steampipe_connection_state OWNER TO root;

--
-- Name: steampipe_plugin; Type: TABLE; Schema: steampipe_internal; Owner: root
--

CREATE TABLE steampipe_internal.steampipe_plugin (
    plugin_instance text,
    plugin text NOT NULL,
    version text,
    memory_max_mb integer,
    limiters jsonb,
    file_name text,
    start_line_number integer,
    end_line_number integer
);


ALTER TABLE steampipe_internal.steampipe_plugin OWNER TO root;

--
-- Name: steampipe_plugin_column; Type: TABLE; Schema: steampipe_internal; Owner: root
--

CREATE TABLE steampipe_internal.steampipe_plugin_column (
    plugin text NOT NULL,
    table_name text NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    description text,
    list_config jsonb,
    get_config jsonb,
    hydrate_name text,
    default_value jsonb
);


ALTER TABLE steampipe_internal.steampipe_plugin_column OWNER TO root;

--
-- Name: steampipe_plugin_limiter; Type: TABLE; Schema: steampipe_internal; Owner: root
--

CREATE TABLE steampipe_internal.steampipe_plugin_limiter (
    name text,
    plugin text,
    plugin_instance text,
    source_type text,
    status text,
    bucket_size integer,
    fill_rate real,
    max_concurrency integer,
    scope jsonb,
    "where" text,
    file_name text,
    start_line_number integer,
    end_line_number integer
);


ALTER TABLE steampipe_internal.steampipe_plugin_limiter OWNER TO root;

--
-- Name: steampipe_scan_metadata; Type: FOREIGN TABLE; Schema: steampipe_internal; Owner: root
--

CREATE FOREIGN TABLE steampipe_internal.steampipe_scan_metadata (
    connection text,
    "table" text,
    cache_hit boolean,
    rows_fetched bigint,
    hydrate_calls bigint,
    start_time timestamp with time zone,
    duration_ms bigint,
    columns jsonb,
    "limit" bigint,
    quals jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'steampipe_scan_metadata'
);


ALTER FOREIGN TABLE steampipe_internal.steampipe_scan_metadata OWNER TO root;

--
-- Name: steampipe_scan_metadata_summary; Type: FOREIGN TABLE; Schema: steampipe_internal; Owner: root
--

CREATE FOREIGN TABLE steampipe_internal.steampipe_scan_metadata_summary (
    cached_rows_fetched bigint,
    uncached_rows_fetched bigint,
    hydrate_calls bigint,
    duration_ms bigint,
    scan_count bigint,
    connection_count bigint
)
SERVER steampipe
OPTIONS (
    "table" 'steampipe_scan_metadata_summary'
);


ALTER FOREIGN TABLE steampipe_internal.steampipe_scan_metadata_summary OWNER TO root;

--
-- Name: steampipe_server_settings; Type: TABLE; Schema: steampipe_internal; Owner: root
--

CREATE TABLE steampipe_internal.steampipe_server_settings (
    start_time timestamp with time zone NOT NULL,
    steampipe_version text NOT NULL,
    fdw_version text NOT NULL,
    cache_max_ttl integer NOT NULL,
    cache_max_size_mb integer NOT NULL,
    cache_enabled boolean NOT NULL
);


ALTER TABLE steampipe_internal.steampipe_server_settings OWNER TO root;

--
-- Name: steampipe_settings; Type: FOREIGN TABLE; Schema: steampipe_internal; Owner: root
--

CREATE FOREIGN TABLE steampipe_internal.steampipe_settings (
    name text,
    value text
)
SERVER steampipe
OPTIONS (
    "table" 'steampipe_settings'
);


ALTER FOREIGN TABLE steampipe_internal.steampipe_settings OWNER TO root;

--
-- Name: taptools_active_listings; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_active_listings (
    listings bigint,
    supply bigint,
    policy text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_active_listings'
);


ALTER FOREIGN TABLE taptools.taptools_active_listings OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_active_listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_active_listings IS 'Get the amount of active listings along with total supply for a particular collection.';


--
-- Name: COLUMN taptools_active_listings.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings.listings IS 'Number of active listings in the collection';


--
-- Name: COLUMN taptools_active_listings.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_active_listings.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_active_listings.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_active_listings.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_active_listings._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_active_listings_individual; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_active_listings_individual (
    image text,
    market text,
    name text,
    price double precision,
    "time" bigint,
    policy text,
    sort_by text,
    order_by text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_active_listings_individual'
);


ALTER FOREIGN TABLE taptools.taptools_active_listings_individual OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_active_listings_individual; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_active_listings_individual IS 'Get a list of active listings with supporting information.';


--
-- Name: COLUMN taptools_active_listings_individual.image; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.image IS 'URL of the NFT''s image';


--
-- Name: COLUMN taptools_active_listings_individual.market; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.market IS 'Marketplace where the NFT is listed';


--
-- Name: COLUMN taptools_active_listings_individual.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.name IS 'Name of the NFT';


--
-- Name: COLUMN taptools_active_listings_individual.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.price IS 'Current listing price of the NFT';


--
-- Name: COLUMN taptools_active_listings_individual."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual."time" IS 'Unix timestamp when the NFT was listed';


--
-- Name: COLUMN taptools_active_listings_individual.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_active_listings_individual.sort_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.sort_by IS 'Example: sortBy=price What should the results be sorted by. Options are price, time. Default is price.';


--
-- Name: COLUMN taptools_active_listings_individual.order_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.order_by IS 'Example: order_by=asc Which direction should the results be sorted. Options are asc, desc. Default is asc';


--
-- Name: COLUMN taptools_active_listings_individual.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_active_listings_individual.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.per_page IS 'Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100.';


--
-- Name: COLUMN taptools_active_listings_individual.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_active_listings_individual.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_active_listings_individual._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_active_listings_individual._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_available_quote_currencies; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_available_quote_currencies (
    currency text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_available_quote_currencies'
);


ALTER FOREIGN TABLE taptools.taptools_available_quote_currencies OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_available_quote_currencies; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_available_quote_currencies IS 'Get all currently available quote currencies.';


--
-- Name: COLUMN taptools_available_quote_currencies.currency; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_available_quote_currencies.currency IS 'Available quote currency';


--
-- Name: COLUMN taptools_available_quote_currencies.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_available_quote_currencies.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_available_quote_currencies.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_available_quote_currencies.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_available_quote_currencies._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_available_quote_currencies._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_collection_assets; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_collection_assets (
    image text,
    name text,
    price double precision,
    rank bigint,
    policy text,
    sort_by text,
    order_by text,
    search text,
    on_sale text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_collection_assets'
);


ALTER FOREIGN TABLE taptools.taptools_collection_assets OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_collection_assets; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_collection_assets IS 'Get all NFTs from a collection with the ability to sort by price/rank and filter to specific traits.';


--
-- Name: COLUMN taptools_collection_assets.image; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.image IS 'URL of the NFT image';


--
-- Name: COLUMN taptools_collection_assets.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.name IS 'Name of the NFT';


--
-- Name: COLUMN taptools_collection_assets.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.price IS 'Current price of the NFT';


--
-- Name: COLUMN taptools_collection_assets.rank; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.rank IS 'Rank of the NFT within the collection';


--
-- Name: COLUMN taptools_collection_assets.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_collection_assets.sort_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.sort_by IS 'Example: sortBy=price What should the results be sorted by. Options are price and rank. Default is price.';


--
-- Name: COLUMN taptools_collection_assets.order_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.order_by IS 'Example: order_by=asc Which direction should the results be sorted. Options are asc, desc. Default is asc';


--
-- Name: COLUMN taptools_collection_assets.search; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.search IS 'Example: search=ClayNation3725 Search for a certain NFT''s name, default is null.';


--
-- Name: COLUMN taptools_collection_assets.on_sale; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.on_sale IS 'Example: onSale=1 Return only nfts that are on sale Options are 0, 1. Default is 0.';


--
-- Name: COLUMN taptools_collection_assets.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_collection_assets.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.per_page IS 'Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100.';


--
-- Name: COLUMN taptools_collection_assets.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_collection_assets.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_collection_assets._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_assets._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_collection_info; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_collection_info (
    description text,
    discord text,
    logo text,
    name text,
    supply bigint,
    twitter text,
    website text,
    policy text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_collection_info'
);


ALTER FOREIGN TABLE taptools.taptools_collection_info OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_collection_info; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_collection_info IS 'Get basic information about a collection like name, socials, and logo.';


--
-- Name: COLUMN taptools_collection_info.description; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.description IS 'Description of the collection';


--
-- Name: COLUMN taptools_collection_info.discord; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.discord IS 'Discord server link for the collection';


--
-- Name: COLUMN taptools_collection_info.logo; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.logo IS 'URL of the collection''s logo';


--
-- Name: COLUMN taptools_collection_info.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.name IS 'Name of the collection';


--
-- Name: COLUMN taptools_collection_info.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_collection_info.twitter; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.twitter IS 'Twitter handle for the collection';


--
-- Name: COLUMN taptools_collection_info.website; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.website IS 'Official website of the collection';


--
-- Name: COLUMN taptools_collection_info.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_collection_info.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_collection_info.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_collection_info._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_info._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_collection_metadata_rarity; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_collection_metadata_rarity (
    category text,
    attribute text,
    probability double precision,
    policy text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_collection_metadata_rarity'
);


ALTER FOREIGN TABLE taptools.taptools_collection_metadata_rarity OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_collection_metadata_rarity; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_collection_metadata_rarity IS 'Get every metadata attribute and how likely it is to occur within the NFT collection.';


--
-- Name: COLUMN taptools_collection_metadata_rarity.category; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity.category IS 'The category of the metadata attribute (e.g., Accessories, Background)';


--
-- Name: COLUMN taptools_collection_metadata_rarity.attribute; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity.attribute IS 'The specific attribute within the category (e.g., Bowtie, Cyan)';


--
-- Name: COLUMN taptools_collection_metadata_rarity.probability; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity.probability IS 'The probability of occurrence for this attribute (e.g., 0.0709)';


--
-- Name: COLUMN taptools_collection_metadata_rarity.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity.policy IS 'The policy ID for the collection. Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e';


--
-- Name: COLUMN taptools_collection_metadata_rarity.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_collection_metadata_rarity.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_collection_metadata_rarity._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_metadata_rarity._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_collection_stats; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_collection_stats (
    listings bigint,
    owners bigint,
    price double precision,
    sales double precision,
    supply bigint,
    top_offer double precision,
    volume double precision,
    policy text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_collection_stats'
);


ALTER FOREIGN TABLE taptools.taptools_collection_stats OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_collection_stats; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_collection_stats IS 'Get basic information about a collection like floor price, volume, and supply.';


--
-- Name: COLUMN taptools_collection_stats.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.listings IS 'Number of current listings for the collection';


--
-- Name: COLUMN taptools_collection_stats.owners; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.owners IS 'Number of unique owners';


--
-- Name: COLUMN taptools_collection_stats.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.price IS 'Current floor price of the collection';


--
-- Name: COLUMN taptools_collection_stats.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.sales IS 'Total number of sales';


--
-- Name: COLUMN taptools_collection_stats.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_collection_stats.top_offer; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.top_offer IS 'Highest offer currently on the collection';


--
-- Name: COLUMN taptools_collection_stats.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.volume IS 'Lifetime trading volume of the collection';


--
-- Name: COLUMN taptools_collection_stats.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_collection_stats.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_collection_stats.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_collection_stats._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_collection_stats_extended; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_collection_stats_extended (
    listings bigint,
    listings_pct_chg double precision,
    owners bigint,
    owners_pct_chg double precision,
    price double precision,
    price_pct_chg double precision,
    sales double precision,
    sales_pct_chg double precision,
    supply bigint,
    top_offer double precision,
    volume double precision,
    volume_pct_chg double precision,
    policy text,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_collection_stats_extended'
);


ALTER FOREIGN TABLE taptools.taptools_collection_stats_extended OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_collection_stats_extended; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_collection_stats_extended IS 'Get extended information about a collection including percentage changes over time.';


--
-- Name: COLUMN taptools_collection_stats_extended.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.listings IS 'Number of current listings for the collection';


--
-- Name: COLUMN taptools_collection_stats_extended.listings_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.listings_pct_chg IS 'Percentage change in listings';


--
-- Name: COLUMN taptools_collection_stats_extended.owners; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.owners IS 'Number of unique owners';


--
-- Name: COLUMN taptools_collection_stats_extended.owners_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.owners_pct_chg IS 'Percentage change in owners';


--
-- Name: COLUMN taptools_collection_stats_extended.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.price IS 'Current floor price of the collection';


--
-- Name: COLUMN taptools_collection_stats_extended.price_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.price_pct_chg IS 'Percentage change in price';


--
-- Name: COLUMN taptools_collection_stats_extended.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.sales IS 'Total number of sales';


--
-- Name: COLUMN taptools_collection_stats_extended.sales_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.sales_pct_chg IS 'Percentage change in sales';


--
-- Name: COLUMN taptools_collection_stats_extended.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_collection_stats_extended.top_offer; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.top_offer IS 'Highest offer currently on the collection';


--
-- Name: COLUMN taptools_collection_stats_extended.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.volume IS 'Lifetime trading volume of the collection';


--
-- Name: COLUMN taptools_collection_stats_extended.volume_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.volume_pct_chg IS 'Percentage change in volume';


--
-- Name: COLUMN taptools_collection_stats_extended.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_collection_stats_extended.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.timeframe IS 'Example: timeframe=24h The time interval. Options are 24h, 7d, 30d. Defaults to 24h.';


--
-- Name: COLUMN taptools_collection_stats_extended.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_collection_stats_extended.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_collection_stats_extended._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_stats_extended._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_collection_trait_prices; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_collection_trait_prices (
    category text,
    trait text,
    price double precision,
    policy text,
    name text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_collection_trait_prices'
);


ALTER FOREIGN TABLE taptools.taptools_collection_trait_prices OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_collection_trait_prices; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_collection_trait_prices IS 'Get a list of traits within a collection and each trait''s floor price.';


--
-- Name: COLUMN taptools_collection_trait_prices.category; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.category IS 'The category of the trait';


--
-- Name: COLUMN taptools_collection_trait_prices.trait; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.trait IS 'The specific trait within the category';


--
-- Name: COLUMN taptools_collection_trait_prices.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.price IS 'The floor price of the trait';


--
-- Name: COLUMN taptools_collection_trait_prices.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_collection_trait_prices.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.name IS 'Example: name=ClayNation3725 The name of a specific NFT to get trait prices for.';


--
-- Name: COLUMN taptools_collection_trait_prices.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_collection_trait_prices.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_collection_trait_prices._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_collection_trait_prices._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_holder_distribution; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_holder_distribution (
    one bigint,
    two_to_four bigint,
    five_to_nine bigint,
    ten_to_twenty_four bigint,
    twenty_five_plus bigint,
    policy text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_holder_distribution'
);


ALTER FOREIGN TABLE taptools.taptools_holder_distribution OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_holder_distribution; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_holder_distribution IS 'Get the distribution of NFTs within a collection by bucketing into number of NFTs held groups.';


--
-- Name: COLUMN taptools_holder_distribution.one; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.one IS 'Number of holders with exactly 1 NFT';


--
-- Name: COLUMN taptools_holder_distribution.two_to_four; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.two_to_four IS 'Number of holders with 2 to 4 NFTs';


--
-- Name: COLUMN taptools_holder_distribution.five_to_nine; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.five_to_nine IS 'Number of holders with 5 to 9 NFTs';


--
-- Name: COLUMN taptools_holder_distribution.ten_to_twenty_four; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.ten_to_twenty_four IS 'Number of holders with 10 to 24 NFTs';


--
-- Name: COLUMN taptools_holder_distribution.twenty_five_plus; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.twenty_five_plus IS 'Number of holders with 25 or more NFTs';


--
-- Name: COLUMN taptools_holder_distribution.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_holder_distribution.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_holder_distribution.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_holder_distribution._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_holder_distribution._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_market_wide_nft_stats; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_market_wide_nft_stats (
    addresses bigint,
    buyers bigint,
    sales bigint,
    sellers bigint,
    volume double precision,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_market_wide_nft_stats'
);


ALTER FOREIGN TABLE taptools.taptools_market_wide_nft_stats OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_market_wide_nft_stats; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_market_wide_nft_stats IS 'Get high-level market stats across the entire NFT market.';


--
-- Name: COLUMN taptools_market_wide_nft_stats.addresses; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.addresses IS 'Count of unique addresses that have engaged in NFT transactions';


--
-- Name: COLUMN taptools_market_wide_nft_stats.buyers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.buyers IS 'Number of unique buyers';


--
-- Name: COLUMN taptools_market_wide_nft_stats.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.sales IS 'Total number of sales';


--
-- Name: COLUMN taptools_market_wide_nft_stats.sellers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.sellers IS 'Number of unique sellers';


--
-- Name: COLUMN taptools_market_wide_nft_stats.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.volume IS 'Total trading volume';


--
-- Name: COLUMN taptools_market_wide_nft_stats.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.timeframe IS 'Example: timeframe=1d The time interval. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.';


--
-- Name: COLUMN taptools_market_wide_nft_stats.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_market_wide_nft_stats.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_market_wide_nft_stats._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_market_wide_nft_stats_extended; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_market_wide_nft_stats_extended (
    addresses bigint,
    addresses_pct_chg double precision,
    buyers bigint,
    buyers_pct_chg double precision,
    sales bigint,
    sales_pct_chg double precision,
    sellers bigint,
    sellers_pct_chg double precision,
    volume double precision,
    volume_pct_chg double precision,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_market_wide_nft_stats_extended'
);


ALTER FOREIGN TABLE taptools.taptools_market_wide_nft_stats_extended OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_market_wide_nft_stats_extended; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_market_wide_nft_stats_extended IS 'Get extended high-level market stats across the entire NFT market.';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.addresses; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.addresses IS 'Count of unique addresses that have engaged in NFT transactions';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.addresses_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.addresses_pct_chg IS 'Percentage change in addresses';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.buyers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.buyers IS 'Number of unique buyers';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.buyers_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.buyers_pct_chg IS 'Percentage change in buyers';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.sales IS 'Total number of sales';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.sales_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.sales_pct_chg IS 'Percentage change in sales';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.sellers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.sellers IS 'Number of unique sellers';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.sellers_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.sellers_pct_chg IS 'Percentage change in sellers';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.volume IS 'Total trading volume';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.volume_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.volume_pct_chg IS 'Percentage change in volume';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.timeframe IS 'Example: timeframe=1d The time interval. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_market_wide_nft_stats_extended._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_market_wide_nft_stats_extended._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_floor_price_ohlcv; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_floor_price_ohlcv (
    close double precision,
    high double precision,
    low double precision,
    open double precision,
    "time" bigint,
    volume double precision,
    policy text,
    "interval" text,
    num_intervals bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_floor_price_ohlcv'
);


ALTER FOREIGN TABLE taptools.taptools_nft_floor_price_ohlcv OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_floor_price_ohlcv; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_floor_price_ohlcv IS 'Get OHLCV (open, high, low, close, volume) of floor price for a particular NFT collection.';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.close; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.close IS 'Closing price for the interval';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.high; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.high IS 'Highest price during the interval';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.low; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.low IS 'Lowest price during the interval';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.open; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.open IS 'Opening price for the interval';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv."time" IS 'Unix timestamp at the start of the interval';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.volume IS 'Volume of trades during the interval';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv."interval"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv."interval" IS 'Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.num_intervals; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.num_intervals IS 'Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here.';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_floor_price_ohlcv._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_floor_price_ohlcv._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_history; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_history (
    buyer_stake_address text,
    price double precision,
    seller_stake_address text,
    "time" bigint,
    policy text,
    name text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_history'
);


ALTER FOREIGN TABLE taptools.taptools_nft_history OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_history; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_history IS 'Get a specific asset''s sale history.';


--
-- Name: COLUMN taptools_nft_history.buyer_stake_address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.buyer_stake_address IS 'Buyer''s stake address';


--
-- Name: COLUMN taptools_nft_history.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.price IS 'Sale price of the NFT';


--
-- Name: COLUMN taptools_nft_history.seller_stake_address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.seller_stake_address IS 'Seller''s stake address';


--
-- Name: COLUMN taptools_nft_history."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history."time" IS 'Unix timestamp of the sale';


--
-- Name: COLUMN taptools_nft_history.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_history.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.name IS 'Example: name=ClayNation3725 The name of a specific NFT to get stats for.';


--
-- Name: COLUMN taptools_nft_history.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_history.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_history._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_history._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_listings_depth; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_listings_depth (
    avg double precision,
    count bigint,
    price double precision,
    total double precision,
    policy text,
    items bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_listings_depth'
);


ALTER FOREIGN TABLE taptools.taptools_nft_listings_depth OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_listings_depth; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_listings_depth IS 'Get cumulative amount of listings at each price point, starting at the floor and moving upwards.';


--
-- Name: COLUMN taptools_nft_listings_depth.avg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.avg IS 'Average price of NFTs at this price point';


--
-- Name: COLUMN taptools_nft_listings_depth.count; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.count IS 'Number of listings at this price point';


--
-- Name: COLUMN taptools_nft_listings_depth.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.price IS 'Price point';


--
-- Name: COLUMN taptools_nft_listings_depth.total; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.total IS 'Total value of NFTs listed at this price point';


--
-- Name: COLUMN taptools_nft_listings_depth.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_listings_depth.items; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.items IS 'Example: items=600 Specify how many items to return. Maximum is 1000, default is 500.';


--
-- Name: COLUMN taptools_nft_listings_depth.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_listings_depth.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_listings_depth._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_depth._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_listings_trended; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_listings_trended (
    listings bigint,
    price double precision,
    "time" bigint,
    policy text,
    "interval" text,
    num_intervals bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_listings_trended'
);


ALTER FOREIGN TABLE taptools.taptools_nft_listings_trended OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_listings_trended; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_listings_trended IS 'Get trended number of listings and floor price for a particular NFT collection.';


--
-- Name: COLUMN taptools_nft_listings_trended.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended.listings IS 'Number of listings at this time point';


--
-- Name: COLUMN taptools_nft_listings_trended.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended.price IS 'Floor price at this time point';


--
-- Name: COLUMN taptools_nft_listings_trended."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended."time" IS 'Unix timestamp for the data point';


--
-- Name: COLUMN taptools_nft_listings_trended.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_listings_trended."interval"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended."interval" IS 'Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.';


--
-- Name: COLUMN taptools_nft_listings_trended.num_intervals; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended.num_intervals IS 'Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here. Leave blank for full history.';


--
-- Name: COLUMN taptools_nft_listings_trended.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_listings_trended.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_listings_trended._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_listings_trended._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_market_volume_trended; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_market_volume_trended (
    "time" bigint,
    value double precision,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_market_volume_trended'
);


ALTER FOREIGN TABLE taptools.taptools_nft_market_volume_trended OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_market_volume_trended; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_market_volume_trended IS 'Get trended volume for entire NFT market.';


--
-- Name: COLUMN taptools_nft_market_volume_trended."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_market_volume_trended."time" IS 'Unix timestamp for the data point';


--
-- Name: COLUMN taptools_nft_market_volume_trended.value; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_market_volume_trended.value IS 'Volume of NFT market transactions for this timeframe';


--
-- Name: COLUMN taptools_nft_market_volume_trended.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_market_volume_trended.timeframe IS 'Example: timeframe=30d The time interval. Options are 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d.';


--
-- Name: COLUMN taptools_nft_market_volume_trended.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_market_volume_trended.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_market_volume_trended.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_market_volume_trended.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_market_volume_trended._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_market_volume_trended._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_marketplace_stats; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_marketplace_stats (
    avg_sale double precision,
    fees double precision,
    liquidity double precision,
    listings bigint,
    name text,
    royalties double precision,
    sales bigint,
    users bigint,
    volume double precision,
    timeframe text,
    marketplace text,
    last_day bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_marketplace_stats'
);


ALTER FOREIGN TABLE taptools.taptools_nft_marketplace_stats OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_marketplace_stats; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_marketplace_stats IS 'Get high-level NFT marketplace stats.';


--
-- Name: COLUMN taptools_nft_marketplace_stats.avg_sale; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.avg_sale IS 'Average sale price';


--
-- Name: COLUMN taptools_nft_marketplace_stats.fees; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.fees IS 'Total fees collected';


--
-- Name: COLUMN taptools_nft_marketplace_stats.liquidity; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.liquidity IS 'Liquidity in the marketplace';


--
-- Name: COLUMN taptools_nft_marketplace_stats.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.listings IS 'Number of current listings';


--
-- Name: COLUMN taptools_nft_marketplace_stats.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.name IS 'Name of the marketplace';


--
-- Name: COLUMN taptools_nft_marketplace_stats.royalties; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.royalties IS 'Total royalties paid';


--
-- Name: COLUMN taptools_nft_marketplace_stats.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.sales IS 'Number of sales';


--
-- Name: COLUMN taptools_nft_marketplace_stats.users; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.users IS 'Number of unique users';


--
-- Name: COLUMN taptools_nft_marketplace_stats.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.volume IS 'Total trading volume';


--
-- Name: COLUMN taptools_nft_marketplace_stats.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.timeframe IS 'Example: timeframe=30d The time interval. Options are 24h, 7d, 30d, 90d, 180d, all. Defaults to 7d.';


--
-- Name: COLUMN taptools_nft_marketplace_stats.marketplace; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.marketplace IS 'Example: marketplace=jpg.store Filters data to a certain marketplace by name.';


--
-- Name: COLUMN taptools_nft_marketplace_stats.last_day; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.last_day IS 'Example: lastDay=0 Filters to only count data that occurred between yesterday 00:00UTC and today 00:00UTC (0,1).';


--
-- Name: COLUMN taptools_nft_marketplace_stats.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_marketplace_stats.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_marketplace_stats._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_marketplace_stats._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_rarity_rank; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_rarity_rank (
    rank bigint,
    policy text,
    name text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_rarity_rank'
);


ALTER FOREIGN TABLE taptools.taptools_nft_rarity_rank OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_rarity_rank; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_rarity_rank IS 'Get rank of NFT''s rarity within a collection';


--
-- Name: COLUMN taptools_nft_rarity_rank.rank; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_rarity_rank.rank IS 'Rarity rank of the NFT within its collection';


--
-- Name: COLUMN taptools_nft_rarity_rank.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_rarity_rank.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_rarity_rank.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_rarity_rank.name IS 'Example: name=ClayNation3725 The name of the NFT';


--
-- Name: COLUMN taptools_nft_rarity_rank.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_rarity_rank.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_rarity_rank.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_rarity_rank.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_rarity_rank._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_rarity_rank._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_stats; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_stats (
    is_listed boolean,
    last_listed_price double precision,
    last_listed_time bigint,
    last_sold_price double precision,
    last_sold_time bigint,
    owners double precision,
    sales double precision,
    times_listed double precision,
    volume double precision,
    policy text,
    name text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_stats'
);


ALTER FOREIGN TABLE taptools.taptools_nft_stats OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_stats; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_stats IS 'Get high-level stats on a certain NFT asset.';


--
-- Name: COLUMN taptools_nft_stats.is_listed; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.is_listed IS 'Whether the NFT is currently listed for sale';


--
-- Name: COLUMN taptools_nft_stats.last_listed_price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.last_listed_price IS 'The price at which the NFT was last listed';


--
-- Name: COLUMN taptools_nft_stats.last_listed_time; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.last_listed_time IS 'Unix timestamp when the NFT was last listed';


--
-- Name: COLUMN taptools_nft_stats.last_sold_price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.last_sold_price IS 'The price at which the NFT was last sold';


--
-- Name: COLUMN taptools_nft_stats.last_sold_time; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.last_sold_time IS 'Unix timestamp when the NFT was last sold';


--
-- Name: COLUMN taptools_nft_stats.owners; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.owners IS 'Number of unique owners of this NFT';


--
-- Name: COLUMN taptools_nft_stats.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.sales IS 'Total number of sales for this NFT';


--
-- Name: COLUMN taptools_nft_stats.times_listed; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.times_listed IS 'Number of times this NFT has been listed';


--
-- Name: COLUMN taptools_nft_stats.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.volume IS 'Total trading volume of this NFT';


--
-- Name: COLUMN taptools_nft_stats.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_stats.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.name IS 'Example: name=ClayNation3725 The name of a specific NFT to get stats for.';


--
-- Name: COLUMN taptools_nft_stats.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_stats.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_stats._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_stats._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_top_rankings; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_top_rankings (
    listings bigint,
    logo text,
    market_cap double precision,
    name text,
    policy text,
    price double precision,
    price_24h_chg double precision,
    price_30d_chg double precision,
    price_7d_chg double precision,
    rank bigint,
    supply bigint,
    volume_24h double precision,
    volume_24h_chg double precision,
    volume_30d double precision,
    volume_30d_chg double precision,
    volume_7d double precision,
    volume_7d_chg double precision,
    ranking text,
    items bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_top_rankings'
);


ALTER FOREIGN TABLE taptools.taptools_nft_top_rankings OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_top_rankings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_top_rankings IS 'Get top NFT rankings based on total market cap, 24 hour volume or 24 hour top price gainers/losers.';


--
-- Name: COLUMN taptools_nft_top_rankings.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.listings IS 'Number of listings for the collection';


--
-- Name: COLUMN taptools_nft_top_rankings.logo; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.logo IS 'URL of the collection''s logo';


--
-- Name: COLUMN taptools_nft_top_rankings.market_cap; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.market_cap IS 'Market capitalization of the collection';


--
-- Name: COLUMN taptools_nft_top_rankings.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.name IS 'Name of the collection';


--
-- Name: COLUMN taptools_nft_top_rankings.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.policy IS 'Policy ID of the collection';


--
-- Name: COLUMN taptools_nft_top_rankings.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.price IS 'Current price';


--
-- Name: COLUMN taptools_nft_top_rankings.price_24h_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.price_24h_chg IS 'Price change in the last 24 hours';


--
-- Name: COLUMN taptools_nft_top_rankings.price_30d_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.price_30d_chg IS 'Price change in the last 30 days';


--
-- Name: COLUMN taptools_nft_top_rankings.price_7d_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.price_7d_chg IS 'Price change in the last 7 days';


--
-- Name: COLUMN taptools_nft_top_rankings.rank; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.rank IS 'Ranking based on specified criteria';


--
-- Name: COLUMN taptools_nft_top_rankings.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_nft_top_rankings.volume_24h; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.volume_24h IS 'Volume traded in the last 24 hours';


--
-- Name: COLUMN taptools_nft_top_rankings.volume_24h_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.volume_24h_chg IS 'Volume change in the last 24 hours';


--
-- Name: COLUMN taptools_nft_top_rankings.volume_30d; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.volume_30d IS 'Volume traded in the last 30 days';


--
-- Name: COLUMN taptools_nft_top_rankings.volume_30d_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.volume_30d_chg IS 'Volume change in the last 30 days';


--
-- Name: COLUMN taptools_nft_top_rankings.volume_7d; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.volume_7d IS 'Volume traded in the last 7 days';


--
-- Name: COLUMN taptools_nft_top_rankings.volume_7d_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.volume_7d_chg IS 'Volume change in the last 7 days';


--
-- Name: COLUMN taptools_nft_top_rankings.ranking; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.ranking IS 'Example: ranking=marketCap Criteria to rank NFT Collections based on. Options are marketCap, volume, gainers, losers.';


--
-- Name: COLUMN taptools_nft_top_rankings.items; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.items IS 'Example: items=50 Specify how many items to return. Maximum is 100, default is 25.';


--
-- Name: COLUMN taptools_nft_top_rankings.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_top_rankings.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_top_rankings._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_top_rankings._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_trades; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_trades (
    buyer_address text,
    collection_name text,
    hash text,
    image text,
    market text,
    name text,
    policy text,
    price double precision,
    seller_address text,
    "time" bigint,
    timeframe text,
    sort_by text,
    order_by text,
    min_amount bigint,
    from_timestamp bigint,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_trades'
);


ALTER FOREIGN TABLE taptools.taptools_nft_trades OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_trades; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_trades IS 'Get individual trades for a particular collection or for the entire NFT market.';


--
-- Name: COLUMN taptools_nft_trades.buyer_address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.buyer_address IS 'Address of the buyer';


--
-- Name: COLUMN taptools_nft_trades.collection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.collection_name IS 'Name of the collection';


--
-- Name: COLUMN taptools_nft_trades.hash; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.hash IS 'Transaction hash of the trade';


--
-- Name: COLUMN taptools_nft_trades.image; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.image IS 'URL of the NFT''s image';


--
-- Name: COLUMN taptools_nft_trades.market; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.market IS 'Marketplace where the trade occurred';


--
-- Name: COLUMN taptools_nft_trades.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.name IS 'Name of the NFT';


--
-- Name: COLUMN taptools_nft_trades.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.policy IS 'Policy ID of the collection';


--
-- Name: COLUMN taptools_nft_trades.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.price IS 'Price of the trade';


--
-- Name: COLUMN taptools_nft_trades.seller_address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.seller_address IS 'Address of the seller';


--
-- Name: COLUMN taptools_nft_trades."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades."time" IS 'Unix timestamp of the trade';


--
-- Name: COLUMN taptools_nft_trades.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.timeframe IS 'Example: timeframe=30d The time interval. Options are 1h, 4h, 24h, 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d.';


--
-- Name: COLUMN taptools_nft_trades.sort_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.sort_by IS 'Example: sortBy=time What should the results be sorted by. Options are amount, time. Default is time.';


--
-- Name: COLUMN taptools_nft_trades.order_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.order_by IS 'Example: order_by=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.';


--
-- Name: COLUMN taptools_nft_trades.min_amount; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.min_amount IS 'Example: min_amount=1000 Filter to only trades of a certain ADA amount.';


--
-- Name: COLUMN taptools_nft_trades.from_timestamp; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.from_timestamp IS 'Example: from_timestamp=1704759422 Filter trades using a UNIX timestamp, will only return trades after this timestamp.';


--
-- Name: COLUMN taptools_nft_trades.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_nft_trades.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.per_page IS 'Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100.';


--
-- Name: COLUMN taptools_nft_trades.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_trades.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_trades._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trades._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_trading_stats; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_trading_stats (
    buyers bigint,
    sales bigint,
    sellers bigint,
    volume double precision,
    policy text,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_trading_stats'
);


ALTER FOREIGN TABLE taptools.taptools_nft_trading_stats OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_trading_stats; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_trading_stats IS 'Get trading stats like volume and number of sales for a particular collection.';


--
-- Name: COLUMN taptools_nft_trading_stats.buyers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.buyers IS 'Number of unique buyers';


--
-- Name: COLUMN taptools_nft_trading_stats.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.sales IS 'Total number of sales';


--
-- Name: COLUMN taptools_nft_trading_stats.sellers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.sellers IS 'Number of unique sellers';


--
-- Name: COLUMN taptools_nft_trading_stats.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.volume IS 'Trading volume within the specified timeframe';


--
-- Name: COLUMN taptools_nft_trading_stats.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_trading_stats.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.timeframe IS 'Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.';


--
-- Name: COLUMN taptools_nft_trading_stats.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_trading_stats.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_trading_stats._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_trading_stats._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_traits; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_traits (
    rank bigint,
    trait_category text,
    trait_name text,
    trait_price double precision,
    trait_rarity double precision,
    policy text,
    name text,
    prices text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_traits'
);


ALTER FOREIGN TABLE taptools.taptools_nft_traits OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_traits; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_traits IS 'Get a specific NFT''s traits and trait prices.';


--
-- Name: COLUMN taptools_nft_traits.rank; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.rank IS 'Rank of the NFT';


--
-- Name: COLUMN taptools_nft_traits.trait_category; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.trait_category IS 'Category of the trait';


--
-- Name: COLUMN taptools_nft_traits.trait_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.trait_name IS 'Name of the trait';


--
-- Name: COLUMN taptools_nft_traits.trait_price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.trait_price IS 'Price of the trait';


--
-- Name: COLUMN taptools_nft_traits.trait_rarity; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.trait_rarity IS 'Rarity of the trait';


--
-- Name: COLUMN taptools_nft_traits.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.policy IS 'The policy ID for the collection. Example: 40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728';


--
-- Name: COLUMN taptools_nft_traits.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.name IS 'The name of a specific NFT to get stats for. Example: ClayNation3725';


--
-- Name: COLUMN taptools_nft_traits.prices; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.prices IS 'Whether to include trait prices (0 or 1). Default is 1. Example: 0';


--
-- Name: COLUMN taptools_nft_traits.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_traits.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_traits._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_traits._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_nft_volume_trended; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_nft_volume_trended (
    price double precision,
    sales bigint,
    "time" bigint,
    volume double precision,
    policy text,
    "interval" text,
    num_intervals bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_nft_volume_trended'
);


ALTER FOREIGN TABLE taptools.taptools_nft_volume_trended OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_nft_volume_trended; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_nft_volume_trended IS 'Get trended volume and number of sales for a particular NFT collection.';


--
-- Name: COLUMN taptools_nft_volume_trended.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.price IS 'Average price for the interval';


--
-- Name: COLUMN taptools_nft_volume_trended.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.sales IS 'Number of sales during the interval';


--
-- Name: COLUMN taptools_nft_volume_trended."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended."time" IS 'Unix timestamp at the start of the interval';


--
-- Name: COLUMN taptools_nft_volume_trended.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.volume IS 'Volume of trades during the interval';


--
-- Name: COLUMN taptools_nft_volume_trended.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.policy IS 'Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.';


--
-- Name: COLUMN taptools_nft_volume_trended."interval"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended."interval" IS 'Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.';


--
-- Name: COLUMN taptools_nft_volume_trended.num_intervals; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.num_intervals IS 'Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here. Leave blank for full history.';


--
-- Name: COLUMN taptools_nft_volume_trended.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_nft_volume_trended.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_nft_volume_trended._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_nft_volume_trended._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_quote_price; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_quote_price (
    price double precision,
    quote text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_quote_price'
);


ALTER FOREIGN TABLE taptools.taptools_quote_price OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_quote_price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_quote_price IS 'Get current quote price (e.g., current ADA/USD price).';


--
-- Name: COLUMN taptools_quote_price.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_quote_price.price IS 'Current price of the quote currency';


--
-- Name: COLUMN taptools_quote_price.quote; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_quote_price.quote IS 'Example: quote=USD Quote currency to use (USD, EUR, ETH, BTC). Default is USD.';


--
-- Name: COLUMN taptools_quote_price.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_quote_price.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_quote_price.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_quote_price.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_quote_price._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_quote_price._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_active_loans; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_active_loans (
    collateral_amount double precision,
    collateral_token text,
    collateral_value double precision,
    debt_amount double precision,
    debt_token text,
    debt_value double precision,
    expiration double precision,
    hash text,
    health double precision,
    interest_amount double precision,
    interest_token text,
    interest_value double precision,
    protocol text,
    "time" bigint,
    unit text,
    include text,
    sort_by text,
    sort_order text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_active_loans'
);


ALTER FOREIGN TABLE taptools.taptools_token_active_loans OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_active_loans; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_active_loans IS 'Get active P2P loans of a certain token (Currently only supports P2P protocols like Lenfi and Levvy).';


--
-- Name: COLUMN taptools_token_active_loans.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_active_loans.include; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.include IS 'Example: include=collateral,debt Comma separated value enabling you to filter to loans where token is used as collateral, debt, interest or a mix of them, default is collateral,debt filtering to loans where token is used as collateral OR debt.';


--
-- Name: COLUMN taptools_token_active_loans.sort_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.sort_by IS 'Example: sortBy=time What should the results be sorted by. Options are time, expiration. Default is time. expiration is expiration date of loan.';


--
-- Name: COLUMN taptools_token_active_loans.sort_order; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.sort_order IS 'Example: sort_order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.';


--
-- Name: COLUMN taptools_token_active_loans.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_active_loans.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.per_page IS 'Example: perPage=100 Specify how many items to return per page, default is 100.';


--
-- Name: COLUMN taptools_token_active_loans.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_active_loans.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_active_loans._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_active_loans._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_holders; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_holders (
    holders bigint,
    unit text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_holders'
);


ALTER FOREIGN TABLE taptools.taptools_token_holders OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_holders; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_holders IS 'Get total number of holders for a specific token. This uses coalesce(stake_address, address), so all addresses under one stake key will be aggregated into 1 holder.';


--
-- Name: COLUMN taptools_token_holders.holders; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_holders.holders IS 'Total number of holders for the specified token';


--
-- Name: COLUMN taptools_token_holders.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_holders.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_holders.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_holders.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_holders.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_holders.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_holders._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_holders._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_links; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_links (
    description text,
    discord text,
    email text,
    facebook text,
    github text,
    instagram text,
    medium text,
    reddit text,
    telegram text,
    twitter text,
    website text,
    youtube text,
    unit text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_links'
);


ALTER FOREIGN TABLE taptools.taptools_token_links OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_links; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_links IS 'Get a specific token''s social links, if they have been provided to TapTools.';


--
-- Name: COLUMN taptools_token_links.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_links.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_links.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_links.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_links.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_links.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_links._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_links._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_liquidity_pools; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_liquidity_pools (
    exchange text,
    lp_token_unit text,
    token_a text,
    token_a_locked double precision,
    token_a_ticker text,
    token_b text,
    token_b_locked double precision,
    token_b_ticker text,
    unit text,
    onchain_id text,
    ada_only bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_liquidity_pools'
);


ALTER FOREIGN TABLE taptools.taptools_token_liquidity_pools OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_liquidity_pools; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_liquidity_pools IS 'Get a specific token''s active liquidity pools. Can search for all token pools using unit or can search for specific pool with onchainID.';


--
-- Name: COLUMN taptools_token_liquidity_pools.exchange; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.exchange IS 'The exchange where the liquidity pool is';


--
-- Name: COLUMN taptools_token_liquidity_pools.lp_token_unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.lp_token_unit IS 'Unit of the liquidity pool token';


--
-- Name: COLUMN taptools_token_liquidity_pools.token_a; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.token_a IS 'Unit of token A in the pool';


--
-- Name: COLUMN taptools_token_liquidity_pools.token_a_locked; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.token_a_locked IS 'Amount of token A locked in the pool';


--
-- Name: COLUMN taptools_token_liquidity_pools.token_a_ticker; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.token_a_ticker IS 'Ticker for token A';


--
-- Name: COLUMN taptools_token_liquidity_pools.token_b; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.token_b IS 'Unit of token B in the pool';


--
-- Name: COLUMN taptools_token_liquidity_pools.token_b_locked; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.token_b_locked IS 'Amount of token B locked in the pool';


--
-- Name: COLUMN taptools_token_liquidity_pools.token_b_ticker; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.token_b_ticker IS 'Ticker for token B';


--
-- Name: COLUMN taptools_token_liquidity_pools.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_liquidity_pools.onchain_id; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.onchain_id IS 'Example: onchainID=0be55d262b29f564998ff81efe21bdc0022621c12f15af08d0f2ddb1.39b9b709ac8605fc82116a2efc308181ba297c11950f0f350001e28f0e50868b Liquidity pool onchainID';


--
-- Name: COLUMN taptools_token_liquidity_pools.ada_only; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.ada_only IS 'Example: adaOnly=1 Return only ADA pools or all pools (0, 1)';


--
-- Name: COLUMN taptools_token_liquidity_pools.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_liquidity_pools.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_liquidity_pools._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_liquidity_pools._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_loan_offers; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_loan_offers (
    collateral_amount double precision,
    collateral_token text,
    collateral_value double precision,
    debt_amount double precision,
    debt_token text,
    debt_value double precision,
    duration bigint,
    hash text,
    health double precision,
    interest_amount double precision,
    interest_token text,
    interest_value double precision,
    protocol text,
    "time" bigint,
    unit text,
    include text,
    sort_by text,
    "order" text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_loan_offers'
);


ALTER FOREIGN TABLE taptools.taptools_token_loan_offers OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_loan_offers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_loan_offers IS 'Get active P2P loan offers that are not associated with any loans yet (Currently only supports P2P protocols like Lenfi and Levvy).';


--
-- Name: COLUMN taptools_token_loan_offers.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name) to filter by';


--
-- Name: COLUMN taptools_token_loan_offers.include; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.include IS 'Example: include=collateral,debt Comma separated value enabling you to filter to offers where token is used as collateral, debt, interest or a mix of them, default is collateral,debt filtering to offers where token is used as collateral OR debt.';


--
-- Name: COLUMN taptools_token_loan_offers.sort_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.sort_by IS 'Example: sortBy=time What should the results be sorted by. Options are time, duration. Default is time. duration is loan duration in seconds.';


--
-- Name: COLUMN taptools_token_loan_offers."order"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers."order" IS 'Example: order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.';


--
-- Name: COLUMN taptools_token_loan_offers.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_loan_offers.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.per_page IS 'Example: perPage=100 Specify how many items to return per page, default is 100.';


--
-- Name: COLUMN taptools_token_loan_offers.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_loan_offers.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_loan_offers._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_loan_offers._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_market_cap; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_market_cap (
    circ_supply double precision,
    fdv double precision,
    mcap double precision,
    price double precision,
    ticker text,
    total_supply double precision,
    unit text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_market_cap'
);


ALTER FOREIGN TABLE taptools.taptools_token_market_cap OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_market_cap; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_market_cap IS 'Get a specific token''s supply and market cap information.';


--
-- Name: COLUMN taptools_token_market_cap.circ_supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.circ_supply IS 'Circulating supply of the token';


--
-- Name: COLUMN taptools_token_market_cap.fdv; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.fdv IS 'Fully diluted valuation of the token';


--
-- Name: COLUMN taptools_token_market_cap.mcap; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.mcap IS 'Market cap of the token';


--
-- Name: COLUMN taptools_token_market_cap.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.price IS 'Current price of the token';


--
-- Name: COLUMN taptools_token_market_cap.ticker; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.ticker IS 'Ticker symbol of the token';


--
-- Name: COLUMN taptools_token_market_cap.total_supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.total_supply IS 'Total supply of the token';


--
-- Name: COLUMN taptools_token_market_cap.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_market_cap.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_market_cap.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_market_cap._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_market_cap._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_price_indicators; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_price_indicators (
    value double precision,
    unit text,
    "interval" text,
    items bigint,
    indicator text,
    length bigint,
    smoothing_factor bigint,
    fast_length bigint,
    slow_length bigint,
    signal_length bigint,
    std_mult bigint,
    quote text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_price_indicators'
);


ALTER FOREIGN TABLE taptools.taptools_token_price_indicators OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_price_indicators; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_price_indicators IS 'Get indicator values (e.g. EMA, RSI) based on price data for a specific token.';


--
-- Name: COLUMN taptools_token_price_indicators.value; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.value IS 'The indicator value';


--
-- Name: COLUMN taptools_token_price_indicators.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_price_indicators."interval"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators."interval" IS 'Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.';


--
-- Name: COLUMN taptools_token_price_indicators.items; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.items IS 'Example: items=100 The number of items to return. The maximum number of items that can be returned is 1000.';


--
-- Name: COLUMN taptools_token_price_indicators.indicator; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.indicator IS 'Example: indicator=ma Specify which indicator to use. Options are ma, ema, rsi, macd, bb, bbw.';


--
-- Name: COLUMN taptools_token_price_indicators.length; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.length IS 'Example: length=14 Length of data to include. Used in ma, ema, rsi, bb, and bbw.';


--
-- Name: COLUMN taptools_token_price_indicators.smoothing_factor; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.smoothing_factor IS 'Example: smoothingFactor=2 Length of data to include for smoothing. Used in ema. Most often is set to 2.';


--
-- Name: COLUMN taptools_token_price_indicators.fast_length; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.fast_length IS 'Example: fastLength=12 Length of shorter EMA to use in MACD. Only used in macd';


--
-- Name: COLUMN taptools_token_price_indicators.slow_length; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.slow_length IS 'Example: slowLength=26 Length of longer EMA to use in MACD. Only used in macd';


--
-- Name: COLUMN taptools_token_price_indicators.signal_length; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.signal_length IS 'Example: signalLength=9 Length of signal EMA to use in MACD. Only used in macd';


--
-- Name: COLUMN taptools_token_price_indicators.std_mult; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.std_mult IS 'Example: stdMult=2 Standard deviation multiplier to use for upper and lower bands of Bollinger Bands (typically set to 2). Used in bb and bbw.';


--
-- Name: COLUMN taptools_token_price_indicators.quote; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.quote IS 'Example: quote=ADA Which quote currency to use when building price data (e.g. ADA, USD).';


--
-- Name: COLUMN taptools_token_price_indicators.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_price_indicators.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_price_indicators._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_indicators._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_price_ohlcv; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_price_ohlcv (
    close double precision,
    high double precision,
    low double precision,
    open double precision,
    volume double precision,
    unit text,
    onchain_id text,
    "interval" text,
    num_intervals bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_price_ohlcv'
);


ALTER FOREIGN TABLE taptools.taptools_token_price_ohlcv OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_price_ohlcv; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_price_ohlcv IS 'Get a specific token''s trended (open, high, low, close, volume) price data. You can either pass a token unit to get aggregated data across all liquidity pools, or an onchainID for a specific pair (see /token/pools).';


--
-- Name: COLUMN taptools_token_price_ohlcv.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_price_ohlcv.onchain_id; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv.onchain_id IS 'Example: onchainID=0be55d262b29f564998ff81efe21bdc0022621c12f15af08d0f2ddb1.39b9b709ac8605fc82116a2efc308181ba297c11950f0f350001e28f0e50868b Pair onchain ID to get ohlc data for';


--
-- Name: COLUMN taptools_token_price_ohlcv."interval"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv."interval" IS 'Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.';


--
-- Name: COLUMN taptools_token_price_ohlcv.num_intervals; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv.num_intervals IS 'Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here.';


--
-- Name: COLUMN taptools_token_price_ohlcv.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_price_ohlcv.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_price_ohlcv._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_ohlcv._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_price_percent_change; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_price_percent_change (
    unit text,
    timeframe text,
    percent_change double precision,
    timeframes text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_price_percent_change'
);


ALTER FOREIGN TABLE taptools.taptools_token_price_percent_change OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_price_percent_change; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_price_percent_change IS 'Get a specific token''s price percent change over various timeframes.';


--
-- Name: COLUMN taptools_token_price_percent_change.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change.unit IS 'Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_price_percent_change.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change.timeframe IS 'Timeframe for which the percent change is calculated';


--
-- Name: COLUMN taptools_token_price_percent_change.percent_change; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change.percent_change IS 'Percent change in price for the specified timeframe';


--
-- Name: COLUMN taptools_token_price_percent_change.timeframes; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change.timeframes IS 'Example: timeframes=1h,4h,24h,7d,30d List of timeframes';


--
-- Name: COLUMN taptools_token_price_percent_change.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_price_percent_change.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_price_percent_change._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_price_percent_change._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_prices; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_prices (
    token text,
    price double precision,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_prices'
);


ALTER FOREIGN TABLE taptools.taptools_token_prices OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_prices; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_prices IS 'Get an object with token units (policy + hex name) as keys and price as values for a list of policies and hex names.';


--
-- Name: COLUMN taptools_token_prices.token; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_prices.token IS 'The token unit (policy + hex name)';


--
-- Name: COLUMN taptools_token_prices.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_prices.price IS 'The current price of the token aggregated across supported DEXs';


--
-- Name: COLUMN taptools_token_prices.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_prices.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_prices.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_prices.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_prices._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_prices._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_top_holders; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_top_holders (
    address text,
    amount bigint,
    policy text,
    page bigint,
    per_page bigint,
    exclude_exchanges bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_top_holders'
);


ALTER FOREIGN TABLE taptools.taptools_token_top_holders OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_top_holders; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_top_holders IS 'Get the top holders for a particular NFT collection.';


--
-- Name: COLUMN taptools_token_top_holders.address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.address IS 'Address of the holder';


--
-- Name: COLUMN taptools_token_top_holders.amount; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.amount IS 'Number of NFTs held by the address';


--
-- Name: COLUMN taptools_token_top_holders.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_token_top_holders.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_top_holders.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.per_page IS 'Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.';


--
-- Name: COLUMN taptools_token_top_holders.exclude_exchanges; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.exclude_exchanges IS 'Example: excludeExchanges=1 Whether or not to exclude marketplace addresses (0, 1)';


--
-- Name: COLUMN taptools_token_top_holders.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_top_holders.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_top_holders._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_holders._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_top_liquidity; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_top_liquidity (
    price double precision,
    ticker text,
    unit text,
    liquidity double precision,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_top_liquidity'
);


ALTER FOREIGN TABLE taptools.taptools_token_top_liquidity OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_top_liquidity; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_top_liquidity IS 'Get tokens ranked by their DEX liquidity. This includes both AMM and order book liquidity.';


--
-- Name: COLUMN taptools_token_top_liquidity.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_liquidity.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_top_liquidity.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_liquidity.per_page IS 'Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.';


--
-- Name: COLUMN taptools_token_top_liquidity.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_liquidity.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_top_liquidity.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_liquidity.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_top_liquidity._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_liquidity._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_top_mcap; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_top_mcap (
    "circSupply" double precision,
    fdv double precision,
    mcap double precision,
    price double precision,
    ticker text,
    "totalSupply" double precision,
    unit text,
    type text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_top_mcap'
);


ALTER FOREIGN TABLE taptools.taptools_token_top_mcap OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_top_mcap; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_top_mcap IS 'Get tokens with top market cap in a descending order. This endpoint does exclude deprecated tokens (e.g. MELD V1 since there was a token migration to MELD V2).';


--
-- Name: COLUMN taptools_token_top_mcap.type; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_mcap.type IS 'Example: type=mcap Sort tokens by circulating market cap or fully diluted value. Options [mcap, fdv].';


--
-- Name: COLUMN taptools_token_top_mcap.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_mcap.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_top_mcap.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_mcap.per_page IS 'Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.';


--
-- Name: COLUMN taptools_token_top_mcap.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_mcap.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_top_mcap.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_mcap.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_top_mcap._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_mcap._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_top_volume; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_top_volume (
    price double precision,
    ticker text,
    unit text,
    volume double precision,
    timeframe text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_top_volume'
);


ALTER FOREIGN TABLE taptools.taptools_token_top_volume OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_top_volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_top_volume IS 'Get tokens with top volume for a given timeframe.';


--
-- Name: COLUMN taptools_token_top_volume.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_volume.timeframe IS 'The timeframe in which to aggregate data.';


--
-- Name: COLUMN taptools_token_top_volume.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_volume.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_top_volume.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_volume.per_page IS 'Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.';


--
-- Name: COLUMN taptools_token_top_volume.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_volume.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_top_volume.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_volume.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_top_volume._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_top_volume._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_token_trades; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_token_trades (
    action text,
    address text,
    exchange text,
    hash text,
    lp_token_unit text,
    price double precision,
    "time" bigint,
    token_a text,
    token_a_amount double precision,
    token_a_name text,
    token_b text,
    token_b_amount double precision,
    token_b_name text,
    timeframe text,
    sort_by text,
    sort_order text,
    unit text,
    min_amount bigint,
    from_timestamp bigint,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_token_trades'
);


ALTER FOREIGN TABLE taptools.taptools_token_trades OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_token_trades; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_token_trades IS 'Get token trades across the entire DEX market.';


--
-- Name: COLUMN taptools_token_trades.action; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.action IS 'Action of the trade';


--
-- Name: COLUMN taptools_token_trades.address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.address IS 'Address involved in the trade';


--
-- Name: COLUMN taptools_token_trades.exchange; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.exchange IS 'Exchange where the trade occurred';


--
-- Name: COLUMN taptools_token_trades.hash; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.hash IS 'Hash of the trade transaction';


--
-- Name: COLUMN taptools_token_trades.lp_token_unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.lp_token_unit IS 'Unit of the liquidity pool token';


--
-- Name: COLUMN taptools_token_trades.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.price IS 'Price of the trade';


--
-- Name: COLUMN taptools_token_trades."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades."time" IS 'Unix timestamp of the trade';


--
-- Name: COLUMN taptools_token_trades.token_a; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.token_a IS 'Token A in the trade';


--
-- Name: COLUMN taptools_token_trades.token_a_amount; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.token_a_amount IS 'Amount of token A traded';


--
-- Name: COLUMN taptools_token_trades.token_a_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.token_a_name IS 'Name of token A';


--
-- Name: COLUMN taptools_token_trades.token_b; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.token_b IS 'Token B in the trade';


--
-- Name: COLUMN taptools_token_trades.token_b_amount; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.token_b_amount IS 'Amount of token B traded';


--
-- Name: COLUMN taptools_token_trades.token_b_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.token_b_name IS 'Name of token B';


--
-- Name: COLUMN taptools_token_trades.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.timeframe IS 'Example: timeframe=30d The time interval. Options are 1h, 4h, 24h, 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d.';


--
-- Name: COLUMN taptools_token_trades.sort_by; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.sort_by IS 'Example: sortBy=amount What should the results be sorted by. Options are amount, time. Default is amount. Filters to only ADA trades if set to amount.';


--
-- Name: COLUMN taptools_token_trades.sort_order; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.sort_order IS 'Example: sort_order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.';


--
-- Name: COLUMN taptools_token_trades.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.unit IS 'Example: unit=279c909f348e533da5808898f87f9a14bb2c3dfbbacccd631d927a3f534e454b Optionally filter to a specific token by specifying a token unit (policy + hex name).';


--
-- Name: COLUMN taptools_token_trades.min_amount; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.min_amount IS 'Example: minAmount=1000 Filter to only trades of a certain ADA amount.';


--
-- Name: COLUMN taptools_token_trades.from_timestamp; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.from_timestamp IS 'Example: from_timestamp=1704759422 Filter trades using a UNIX timestamp, will only return trades after this timestamp.';


--
-- Name: COLUMN taptools_token_trades.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_token_trades.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.per_page IS 'Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.';


--
-- Name: COLUMN taptools_token_trades.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_token_trades.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_token_trades._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_token_trades._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_top_holders; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_top_holders (
    address text,
    amount double precision,
    unit text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_top_holders'
);


ALTER FOREIGN TABLE taptools.taptools_top_holders OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_top_holders; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_top_holders IS 'Get top token holders.';


--
-- Name: COLUMN taptools_top_holders.address; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.address IS 'The address of the token holder';


--
-- Name: COLUMN taptools_top_holders.amount; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.amount IS 'The amount of tokens held by this address';


--
-- Name: COLUMN taptools_top_holders.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_top_holders.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_top_holders.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.per_page IS 'Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.';


--
-- Name: COLUMN taptools_top_holders.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_top_holders.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_top_holders._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_holders._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_top_volume_collections; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_top_volume_collections (
    listings bigint,
    logo text,
    name text,
    policy text,
    price double precision,
    sales bigint,
    supply bigint,
    volume double precision,
    timeframe text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_top_volume_collections'
);


ALTER FOREIGN TABLE taptools.taptools_top_volume_collections OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_top_volume_collections; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_top_volume_collections IS 'Get top NFT collections by trading volume over a given timeframe.';


--
-- Name: COLUMN taptools_top_volume_collections.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.listings IS 'Number of current listings for the collection';


--
-- Name: COLUMN taptools_top_volume_collections.logo; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.logo IS 'URL of the collection''s logo';


--
-- Name: COLUMN taptools_top_volume_collections.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.name IS 'Name of the collection';


--
-- Name: COLUMN taptools_top_volume_collections.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.policy IS 'Policy ID of the collection';


--
-- Name: COLUMN taptools_top_volume_collections.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.price IS 'Current price of the collection';


--
-- Name: COLUMN taptools_top_volume_collections.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.sales IS 'Number of sales';


--
-- Name: COLUMN taptools_top_volume_collections.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_top_volume_collections.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.volume IS 'Trading volume of the collection';


--
-- Name: COLUMN taptools_top_volume_collections.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.timeframe IS 'Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.';


--
-- Name: COLUMN taptools_top_volume_collections.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_top_volume_collections.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.per_page IS 'Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.';


--
-- Name: COLUMN taptools_top_volume_collections.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_top_volume_collections.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_top_volume_collections._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_top_volume_collections_extended; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_top_volume_collections_extended (
    listings bigint,
    listings_pct_chg double precision,
    logo text,
    name text,
    owners bigint,
    owners_pct_chg double precision,
    policy text,
    price double precision,
    price_pct_chg double precision,
    sales bigint,
    sales_pct_chg double precision,
    supply bigint,
    volume double precision,
    volume_pct_chg double precision,
    timeframe text,
    page bigint,
    per_page bigint,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_top_volume_collections_extended'
);


ALTER FOREIGN TABLE taptools.taptools_top_volume_collections_extended OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_top_volume_collections_extended; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_top_volume_collections_extended IS 'Get top NFT collections by trading volume over a given timeframe, including percentage changes.';


--
-- Name: COLUMN taptools_top_volume_collections_extended.listings; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.listings IS 'Number of current listings for the collection';


--
-- Name: COLUMN taptools_top_volume_collections_extended.listings_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.listings_pct_chg IS 'Percentage change in listings';


--
-- Name: COLUMN taptools_top_volume_collections_extended.logo; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.logo IS 'URL of the collection''s logo';


--
-- Name: COLUMN taptools_top_volume_collections_extended.name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.name IS 'Name of the collection';


--
-- Name: COLUMN taptools_top_volume_collections_extended.owners; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.owners IS 'Number of unique owners';


--
-- Name: COLUMN taptools_top_volume_collections_extended.owners_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.owners_pct_chg IS 'Percentage change in owners';


--
-- Name: COLUMN taptools_top_volume_collections_extended.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.policy IS 'Policy ID of the collection';


--
-- Name: COLUMN taptools_top_volume_collections_extended.price; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.price IS 'Current price of the collection';


--
-- Name: COLUMN taptools_top_volume_collections_extended.price_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.price_pct_chg IS 'Percentage change in price';


--
-- Name: COLUMN taptools_top_volume_collections_extended.sales; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.sales IS 'Number of sales';


--
-- Name: COLUMN taptools_top_volume_collections_extended.sales_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.sales_pct_chg IS 'Percentage change in sales';


--
-- Name: COLUMN taptools_top_volume_collections_extended.supply; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.supply IS 'Total supply of NFTs in the collection';


--
-- Name: COLUMN taptools_top_volume_collections_extended.volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.volume IS 'Trading volume of the collection';


--
-- Name: COLUMN taptools_top_volume_collections_extended.volume_pct_chg; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.volume_pct_chg IS 'Percentage change in volume';


--
-- Name: COLUMN taptools_top_volume_collections_extended.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.timeframe IS 'Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.';


--
-- Name: COLUMN taptools_top_volume_collections_extended.page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.page IS 'Example: page=1 This endpoint supports pagination. Default page is 1.';


--
-- Name: COLUMN taptools_top_volume_collections_extended.per_page; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.per_page IS 'Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.';


--
-- Name: COLUMN taptools_top_volume_collections_extended.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_top_volume_collections_extended.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_top_volume_collections_extended._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_top_volume_collections_extended._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_trading_stats; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_trading_stats (
    buy_volume double precision,
    buyers bigint,
    buys bigint,
    sell_volume double precision,
    sellers bigint,
    sells bigint,
    unit text,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_trading_stats'
);


ALTER FOREIGN TABLE taptools.taptools_trading_stats OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_trading_stats; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_trading_stats IS 'Get aggregated trading stats for a particular token.';


--
-- Name: COLUMN taptools_trading_stats.buy_volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.buy_volume IS 'Total volume of buys';


--
-- Name: COLUMN taptools_trading_stats.buyers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.buyers IS 'Number of unique buyers';


--
-- Name: COLUMN taptools_trading_stats.buys; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.buys IS 'Number of buy transactions';


--
-- Name: COLUMN taptools_trading_stats.sell_volume; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.sell_volume IS 'Total volume of sells';


--
-- Name: COLUMN taptools_trading_stats.sellers; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.sellers IS 'Number of unique sellers';


--
-- Name: COLUMN taptools_trading_stats.sells; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.sells IS 'Number of sell transactions';


--
-- Name: COLUMN taptools_trading_stats.unit; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.unit IS 'Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)';


--
-- Name: COLUMN taptools_trading_stats.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.timeframe IS 'Example: timeframe=24h Specify a timeframe in which to aggregate the data by. Options are [15m, 1h, 4h, 12h, 24h, 7d, 30d, 90d, 180d, 1y, all]. Default is 24h.';


--
-- Name: COLUMN taptools_trading_stats.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_trading_stats.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_trading_stats._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trading_stats._ctx IS 'Steampipe context in JSON form.';


--
-- Name: taptools_trended_holders; Type: FOREIGN TABLE; Schema: taptools; Owner: root
--

CREATE FOREIGN TABLE taptools.taptools_trended_holders (
    holders bigint,
    "time" bigint,
    policy text,
    timeframe text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'taptools_trended_holders'
);


ALTER FOREIGN TABLE taptools.taptools_trended_holders OWNER TO root;

--
-- Name: FOREIGN TABLE taptools_trended_holders; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON FOREIGN TABLE taptools.taptools_trended_holders IS 'Get holders trended by day for a particular NFT collection.';


--
-- Name: COLUMN taptools_trended_holders.holders; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders.holders IS 'Number of holders at this time point';


--
-- Name: COLUMN taptools_trended_holders."time"; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders."time" IS 'Unix timestamp for the data point';


--
-- Name: COLUMN taptools_trended_holders.policy; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders.policy IS 'Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.';


--
-- Name: COLUMN taptools_trended_holders.timeframe; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders.timeframe IS 'Example: timeframe=30d The time interval. Options are 7d, 30d, 90d, 180d, 1y and all. Defaults to 30d.';


--
-- Name: COLUMN taptools_trended_holders.sp_connection_name; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN taptools_trended_holders.sp_ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN taptools_trended_holders._ctx; Type: COMMENT; Schema: taptools; Owner: root
--

COMMENT ON COLUMN taptools.taptools_trended_holders._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_search_recent; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_search_recent (
    id text,
    text text,
    author_id text,
    conversation_id text,
    created_at timestamp with time zone,
    in_reply_to_user_id text,
    replied_to text,
    retweeted text,
    quoted text,
    mentions jsonb,
    hashtags jsonb,
    urls jsonb,
    cashtags jsonb,
    entities jsonb,
    attachments jsonb,
    geo jsonb,
    context_annotations jsonb,
    withheld jsonb,
    public_metrics jsonb,
    possibly_sensitive boolean,
    lang text,
    source text,
    author jsonb,
    in_reply_user jsonb,
    place jsonb,
    attachment_polls jsonb,
    mentions_obj jsonb,
    referenced_tweets jsonb,
    query text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_search_recent'
);


ALTER FOREIGN TABLE twitter.twitter_search_recent OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_search_recent; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_search_recent IS 'Search public Tweets posted over the last 7 days.';


--
-- Name: COLUMN twitter_search_recent.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.id IS 'Unique identifier of this Tweet.';


--
-- Name: COLUMN twitter_search_recent.text; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.text IS 'The content of the Tweet.';


--
-- Name: COLUMN twitter_search_recent.author_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.author_id IS 'Unique identifier of the author of the Tweet.';


--
-- Name: COLUMN twitter_search_recent.conversation_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.conversation_id IS 'The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).';


--
-- Name: COLUMN twitter_search_recent.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.created_at IS 'Creation time of the Tweet.';


--
-- Name: COLUMN twitter_search_recent.in_reply_to_user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.in_reply_to_user_id IS 'If this Tweet is a Reply, indicates the user ID of the parent Tweet''s author.';


--
-- Name: COLUMN twitter_search_recent.replied_to; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.replied_to IS 'If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.';


--
-- Name: COLUMN twitter_search_recent.retweeted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.retweeted IS 'If this Tweet is a Retweet, indicates the ID of the orginal Tweet.';


--
-- Name: COLUMN twitter_search_recent.quoted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.quoted IS 'If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.';


--
-- Name: COLUMN twitter_search_recent.mentions; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.mentions IS 'List of users (e.g. steampipeio) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_search_recent.hashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.hashtags IS 'List of hashtags (e.g. #sql) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_search_recent.urls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.urls IS 'List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_search_recent.cashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.cashtags IS 'List of cashtags (e.g. $TWTR) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_search_recent.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.entities IS 'Contains details about text that has a special meaning in a Tweet.';


--
-- Name: COLUMN twitter_search_recent.attachments; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.attachments IS 'Specifies the type of attachments (if any) present in this Tweet.';


--
-- Name: COLUMN twitter_search_recent.geo; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.geo IS 'Contains details about the location tagged by the user in this Tweet, if they specified one.';


--
-- Name: COLUMN twitter_search_recent.context_annotations; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.context_annotations IS 'Contains context annotations for the Tweet.';


--
-- Name: COLUMN twitter_search_recent.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.withheld IS 'Contains withholding details for withheld content.';


--
-- Name: COLUMN twitter_search_recent.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.public_metrics IS 'Engagement metrics for the Tweet at the time of the request.';


--
-- Name: COLUMN twitter_search_recent.possibly_sensitive; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.possibly_sensitive IS 'Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.';


--
-- Name: COLUMN twitter_search_recent.lang; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.lang IS 'Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.';


--
-- Name: COLUMN twitter_search_recent.source; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.source IS 'The name of the app the user Tweeted from.';


--
-- Name: COLUMN twitter_search_recent.author; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.author IS 'Author of the Tweet.';


--
-- Name: COLUMN twitter_search_recent.in_reply_user; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.in_reply_user IS 'User the Tweet was in reply to.';


--
-- Name: COLUMN twitter_search_recent.place; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.place IS 'Place where the Tweet was created.';


--
-- Name: COLUMN twitter_search_recent.attachment_polls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.attachment_polls IS 'Polls attached to the Tweet.';


--
-- Name: COLUMN twitter_search_recent.mentions_obj; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.mentions_obj IS 'Users mentioned in the Tweet.';


--
-- Name: COLUMN twitter_search_recent.referenced_tweets; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.referenced_tweets IS 'Tweets referenced in this Tweet.';


--
-- Name: COLUMN twitter_search_recent.query; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.query IS 'Query string for the exploit search.';


--
-- Name: COLUMN twitter_search_recent.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_search_recent.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_search_recent._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_search_recent._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_tweet; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_tweet (
    id text,
    text text,
    author_id text,
    conversation_id text,
    created_at timestamp with time zone,
    in_reply_to_user_id text,
    replied_to text,
    retweeted text,
    quoted text,
    mentions jsonb,
    hashtags jsonb,
    urls jsonb,
    cashtags jsonb,
    entities jsonb,
    attachments jsonb,
    geo jsonb,
    context_annotations jsonb,
    withheld jsonb,
    public_metrics jsonb,
    possibly_sensitive boolean,
    lang text,
    source text,
    author jsonb,
    in_reply_user jsonb,
    place jsonb,
    attachment_polls jsonb,
    mentions_obj jsonb,
    referenced_tweets jsonb,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_tweet'
);


ALTER FOREIGN TABLE twitter.twitter_tweet OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_tweet; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_tweet IS 'Lookup a specific tweet by ID.';


--
-- Name: COLUMN twitter_tweet.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.id IS 'Unique identifier of this Tweet.';


--
-- Name: COLUMN twitter_tweet.text; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.text IS 'The content of the Tweet.';


--
-- Name: COLUMN twitter_tweet.author_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.author_id IS 'Unique identifier of the author of the Tweet.';


--
-- Name: COLUMN twitter_tweet.conversation_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.conversation_id IS 'The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).';


--
-- Name: COLUMN twitter_tweet.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.created_at IS 'Creation time of the Tweet.';


--
-- Name: COLUMN twitter_tweet.in_reply_to_user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.in_reply_to_user_id IS 'If this Tweet is a Reply, indicates the user ID of the parent Tweet''s author.';


--
-- Name: COLUMN twitter_tweet.replied_to; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.replied_to IS 'If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.';


--
-- Name: COLUMN twitter_tweet.retweeted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.retweeted IS 'If this Tweet is a Retweet, indicates the ID of the orginal Tweet.';


--
-- Name: COLUMN twitter_tweet.quoted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.quoted IS 'If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.';


--
-- Name: COLUMN twitter_tweet.mentions; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.mentions IS 'List of users (e.g. steampipeio) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_tweet.hashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.hashtags IS 'List of hashtags (e.g. #sql) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_tweet.urls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.urls IS 'List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_tweet.cashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.cashtags IS 'List of cashtags (e.g. $TWTR) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_tweet.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.entities IS 'Contains details about text that has a special meaning in a Tweet.';


--
-- Name: COLUMN twitter_tweet.attachments; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.attachments IS 'Specifies the type of attachments (if any) present in this Tweet.';


--
-- Name: COLUMN twitter_tweet.geo; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.geo IS 'Contains details about the location tagged by the user in this Tweet, if they specified one.';


--
-- Name: COLUMN twitter_tweet.context_annotations; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.context_annotations IS 'Contains context annotations for the Tweet.';


--
-- Name: COLUMN twitter_tweet.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.withheld IS 'Contains withholding details for withheld content.';


--
-- Name: COLUMN twitter_tweet.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.public_metrics IS 'Engagement metrics for the Tweet at the time of the request.';


--
-- Name: COLUMN twitter_tweet.possibly_sensitive; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.possibly_sensitive IS 'Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.';


--
-- Name: COLUMN twitter_tweet.lang; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.lang IS 'Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.';


--
-- Name: COLUMN twitter_tweet.source; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.source IS 'The name of the app the user Tweeted from.';


--
-- Name: COLUMN twitter_tweet.author; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.author IS 'Author of the Tweet.';


--
-- Name: COLUMN twitter_tweet.in_reply_user; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.in_reply_user IS 'User the Tweet was in reply to.';


--
-- Name: COLUMN twitter_tweet.place; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.place IS 'Place where the Tweet was created.';


--
-- Name: COLUMN twitter_tweet.attachment_polls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.attachment_polls IS 'Polls attached to the Tweet.';


--
-- Name: COLUMN twitter_tweet.mentions_obj; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.mentions_obj IS 'Users mentioned in the Tweet.';


--
-- Name: COLUMN twitter_tweet.referenced_tweets; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.referenced_tweets IS 'Tweets referenced in this Tweet.';


--
-- Name: COLUMN twitter_tweet.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_tweet.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_tweet._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_tweet._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_user; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_user (
    id text,
    name text,
    username text,
    created_at timestamp with time zone,
    description text,
    entities jsonb,
    location text,
    pinned_tweet jsonb,
    pinned_tweet_id text,
    profile_image_url text,
    protected text,
    public_metrics jsonb,
    url text,
    verified boolean,
    withheld jsonb,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_user'
);


ALTER FOREIGN TABLE twitter.twitter_user OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_user; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_user IS 'Lookup a specific user by ID or username.';


--
-- Name: COLUMN twitter_user.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.id IS 'The unique identifier of this user.';


--
-- Name: COLUMN twitter_user.name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.name IS 'The name of the user, as they’ve defined it on their profile. Not necessarily a person’s name.';


--
-- Name: COLUMN twitter_user.username; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.username IS 'The Twitter screen name, handle, or alias that this user identifies themselves with. Usernames are unique but subject to change.';


--
-- Name: COLUMN twitter_user.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.created_at IS 'The UTC datetime that the user account was created on Twitter.';


--
-- Name: COLUMN twitter_user.description; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.description IS 'The text of this user''s profile description (also known as bio), if the user provided one.';


--
-- Name: COLUMN twitter_user.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.entities IS 'Entities are JSON objects that provide additional information about hashtags, urls, user mentions, and cashtags associated with the description.';


--
-- Name: COLUMN twitter_user.location; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.location IS 'The location specified in the user''s profile, if the user provided one. As this is a freeform value, it may not indicate a valid location, but it may be fuzzily evaluated when performing searches with location queries.';


--
-- Name: COLUMN twitter_user.pinned_tweet; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.pinned_tweet IS 'Contains withholding details for withheld content, if applicable.';


--
-- Name: COLUMN twitter_user.pinned_tweet_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.pinned_tweet_id IS 'Unique identifier of this user''s pinned Tweet.';


--
-- Name: COLUMN twitter_user.profile_image_url; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.profile_image_url IS 'The URL to the profile image for this user, as shown on the user''s profile.';


--
-- Name: COLUMN twitter_user.protected; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.protected IS 'Indicates if this user has chosen to protect their Tweets (in other words, if this user''s Tweets are private).';


--
-- Name: COLUMN twitter_user.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.public_metrics IS 'Contains details about activity for this user.';


--
-- Name: COLUMN twitter_user.url; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.url IS 'The URL specified in the user''s profile, if present.';


--
-- Name: COLUMN twitter_user.verified; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.verified IS 'Indicates if this user is a verified Twitter User.';


--
-- Name: COLUMN twitter_user.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.withheld IS 'Contains withholding details for withheld content, if applicable.';


--
-- Name: COLUMN twitter_user.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_user.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_user._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_user_follower; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_user_follower (
    id text,
    name text,
    username text,
    created_at timestamp with time zone,
    description text,
    entities jsonb,
    location text,
    pinned_tweet jsonb,
    pinned_tweet_id text,
    profile_image_url text,
    protected text,
    public_metrics jsonb,
    url text,
    verified boolean,
    withheld jsonb,
    user_id text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_user_follower'
);


ALTER FOREIGN TABLE twitter.twitter_user_follower OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_user_follower; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_user_follower IS 'List of users the specified user ID is follower.';


--
-- Name: COLUMN twitter_user_follower.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.id IS 'The unique identifier of this user.';


--
-- Name: COLUMN twitter_user_follower.name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.name IS 'The name of the user, as they’ve defined it on their profile. Not necessarily a person’s name.';


--
-- Name: COLUMN twitter_user_follower.username; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.username IS 'The Twitter screen name, handle, or alias that this user identifies themselves with. Usernames are unique but subject to change.';


--
-- Name: COLUMN twitter_user_follower.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.created_at IS 'The UTC datetime that the user account was created on Twitter.';


--
-- Name: COLUMN twitter_user_follower.description; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.description IS 'The text of this user''s profile description (also known as bio), if the user provided one.';


--
-- Name: COLUMN twitter_user_follower.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.entities IS 'Entities are JSON objects that provide additional information about hashtags, urls, user mentions, and cashtags associated with the description.';


--
-- Name: COLUMN twitter_user_follower.location; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.location IS 'The location specified in the user''s profile, if the user provided one. As this is a freeform value, it may not indicate a valid location, but it may be fuzzily evaluated when performing searches with location queries.';


--
-- Name: COLUMN twitter_user_follower.pinned_tweet; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.pinned_tweet IS 'Contains withholding details for withheld content, if applicable.';


--
-- Name: COLUMN twitter_user_follower.pinned_tweet_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.pinned_tweet_id IS 'Unique identifier of this user''s pinned Tweet.';


--
-- Name: COLUMN twitter_user_follower.profile_image_url; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.profile_image_url IS 'The URL to the profile image for this user, as shown on the user''s profile.';


--
-- Name: COLUMN twitter_user_follower.protected; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.protected IS 'Indicates if this user has chosen to protect their Tweets (in other words, if this user''s Tweets are private).';


--
-- Name: COLUMN twitter_user_follower.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.public_metrics IS 'Contains details about activity for this user.';


--
-- Name: COLUMN twitter_user_follower.url; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.url IS 'The URL specified in the user''s profile, if present.';


--
-- Name: COLUMN twitter_user_follower.verified; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.verified IS 'Indicates if this user is a verified Twitter User.';


--
-- Name: COLUMN twitter_user_follower.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.withheld IS 'Contains withholding details for withheld content, if applicable.';


--
-- Name: COLUMN twitter_user_follower.user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.user_id IS 'ID of the user who is followed by these users.';


--
-- Name: COLUMN twitter_user_follower.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_user_follower.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_user_follower._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_follower._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_user_following; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_user_following (
    id text,
    name text,
    username text,
    created_at timestamp with time zone,
    description text,
    entities jsonb,
    location text,
    pinned_tweet jsonb,
    pinned_tweet_id text,
    profile_image_url text,
    protected text,
    public_metrics jsonb,
    url text,
    verified boolean,
    withheld jsonb,
    user_id text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_user_following'
);


ALTER FOREIGN TABLE twitter.twitter_user_following OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_user_following; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_user_following IS 'List of users the specified user ID is following.';


--
-- Name: COLUMN twitter_user_following.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.id IS 'The unique identifier of this user.';


--
-- Name: COLUMN twitter_user_following.name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.name IS 'The name of the user, as they’ve defined it on their profile. Not necessarily a person’s name.';


--
-- Name: COLUMN twitter_user_following.username; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.username IS 'The Twitter screen name, handle, or alias that this user identifies themselves with. Usernames are unique but subject to change.';


--
-- Name: COLUMN twitter_user_following.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.created_at IS 'The UTC datetime that the user account was created on Twitter.';


--
-- Name: COLUMN twitter_user_following.description; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.description IS 'The text of this user''s profile description (also known as bio), if the user provided one.';


--
-- Name: COLUMN twitter_user_following.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.entities IS 'Entities are JSON objects that provide additional information about hashtags, urls, user mentions, and cashtags associated with the description.';


--
-- Name: COLUMN twitter_user_following.location; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.location IS 'The location specified in the user''s profile, if the user provided one. As this is a freeform value, it may not indicate a valid location, but it may be fuzzily evaluated when performing searches with location queries.';


--
-- Name: COLUMN twitter_user_following.pinned_tweet; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.pinned_tweet IS 'Contains withholding details for withheld content, if applicable.';


--
-- Name: COLUMN twitter_user_following.pinned_tweet_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.pinned_tweet_id IS 'Unique identifier of this user''s pinned Tweet.';


--
-- Name: COLUMN twitter_user_following.profile_image_url; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.profile_image_url IS 'The URL to the profile image for this user, as shown on the user''s profile.';


--
-- Name: COLUMN twitter_user_following.protected; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.protected IS 'Indicates if this user has chosen to protect their Tweets (in other words, if this user''s Tweets are private).';


--
-- Name: COLUMN twitter_user_following.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.public_metrics IS 'Contains details about activity for this user.';


--
-- Name: COLUMN twitter_user_following.url; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.url IS 'The URL specified in the user''s profile, if present.';


--
-- Name: COLUMN twitter_user_following.verified; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.verified IS 'Indicates if this user is a verified Twitter User.';


--
-- Name: COLUMN twitter_user_following.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.withheld IS 'Contains withholding details for withheld content, if applicable.';


--
-- Name: COLUMN twitter_user_following.user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.user_id IS 'ID of the user who is followed by these users.';


--
-- Name: COLUMN twitter_user_following.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_user_following.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_user_following._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_following._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_user_mention; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_user_mention (
    id text,
    text text,
    author_id text,
    conversation_id text,
    created_at timestamp with time zone,
    in_reply_to_user_id text,
    replied_to text,
    retweeted text,
    quoted text,
    mentions jsonb,
    hashtags jsonb,
    urls jsonb,
    cashtags jsonb,
    entities jsonb,
    attachments jsonb,
    geo jsonb,
    context_annotations jsonb,
    withheld jsonb,
    public_metrics jsonb,
    possibly_sensitive boolean,
    lang text,
    source text,
    author jsonb,
    in_reply_user jsonb,
    place jsonb,
    attachment_polls jsonb,
    mentions_obj jsonb,
    referenced_tweets jsonb,
    user_id text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_user_mention'
);


ALTER FOREIGN TABLE twitter.twitter_user_mention OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_user_mention; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_user_mention IS 'The user mention timeline lists Tweets mentioning a specific Twitter user, for example, if a Twitter account mentioned @TwitterDev within a Tweet. This will also include replies to Tweets by the user requested.';


--
-- Name: COLUMN twitter_user_mention.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.id IS 'Unique identifier of this Tweet.';


--
-- Name: COLUMN twitter_user_mention.text; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.text IS 'The content of the Tweet.';


--
-- Name: COLUMN twitter_user_mention.author_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.author_id IS 'Unique identifier of the author of the Tweet.';


--
-- Name: COLUMN twitter_user_mention.conversation_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.conversation_id IS 'The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).';


--
-- Name: COLUMN twitter_user_mention.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.created_at IS 'Creation time of the Tweet.';


--
-- Name: COLUMN twitter_user_mention.in_reply_to_user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.in_reply_to_user_id IS 'If this Tweet is a Reply, indicates the user ID of the parent Tweet''s author.';


--
-- Name: COLUMN twitter_user_mention.replied_to; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.replied_to IS 'If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.';


--
-- Name: COLUMN twitter_user_mention.retweeted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.retweeted IS 'If this Tweet is a Retweet, indicates the ID of the orginal Tweet.';


--
-- Name: COLUMN twitter_user_mention.quoted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.quoted IS 'If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.';


--
-- Name: COLUMN twitter_user_mention.mentions; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.mentions IS 'List of users (e.g. steampipeio) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_mention.hashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.hashtags IS 'List of hashtags (e.g. #sql) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_mention.urls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.urls IS 'List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_mention.cashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.cashtags IS 'List of cashtags (e.g. $TWTR) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_mention.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.entities IS 'Contains details about text that has a special meaning in a Tweet.';


--
-- Name: COLUMN twitter_user_mention.attachments; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.attachments IS 'Specifies the type of attachments (if any) present in this Tweet.';


--
-- Name: COLUMN twitter_user_mention.geo; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.geo IS 'Contains details about the location tagged by the user in this Tweet, if they specified one.';


--
-- Name: COLUMN twitter_user_mention.context_annotations; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.context_annotations IS 'Contains context annotations for the Tweet.';


--
-- Name: COLUMN twitter_user_mention.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.withheld IS 'Contains withholding details for withheld content.';


--
-- Name: COLUMN twitter_user_mention.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.public_metrics IS 'Engagement metrics for the Tweet at the time of the request.';


--
-- Name: COLUMN twitter_user_mention.possibly_sensitive; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.possibly_sensitive IS 'Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.';


--
-- Name: COLUMN twitter_user_mention.lang; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.lang IS 'Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.';


--
-- Name: COLUMN twitter_user_mention.source; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.source IS 'The name of the app the user Tweeted from.';


--
-- Name: COLUMN twitter_user_mention.author; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.author IS 'Author of the Tweet.';


--
-- Name: COLUMN twitter_user_mention.in_reply_user; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.in_reply_user IS 'User the Tweet was in reply to.';


--
-- Name: COLUMN twitter_user_mention.place; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.place IS 'Place where the Tweet was created.';


--
-- Name: COLUMN twitter_user_mention.attachment_polls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.attachment_polls IS 'Polls attached to the Tweet.';


--
-- Name: COLUMN twitter_user_mention.mentions_obj; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.mentions_obj IS 'Users mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_mention.referenced_tweets; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.referenced_tweets IS 'Tweets referenced in this Tweet.';


--
-- Name: COLUMN twitter_user_mention.user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.user_id IS 'ID of the user the tweets are related to.';


--
-- Name: COLUMN twitter_user_mention.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_user_mention.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_user_mention._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_mention._ctx IS 'Steampipe context in JSON form.';


--
-- Name: twitter_user_tweet; Type: FOREIGN TABLE; Schema: twitter; Owner: root
--

CREATE FOREIGN TABLE twitter.twitter_user_tweet (
    id text,
    text text,
    author_id text,
    conversation_id text,
    created_at timestamp with time zone,
    in_reply_to_user_id text,
    replied_to text,
    retweeted text,
    quoted text,
    mentions jsonb,
    hashtags jsonb,
    urls jsonb,
    cashtags jsonb,
    entities jsonb,
    attachments jsonb,
    geo jsonb,
    context_annotations jsonb,
    withheld jsonb,
    public_metrics jsonb,
    possibly_sensitive boolean,
    lang text,
    source text,
    author jsonb,
    in_reply_user jsonb,
    place jsonb,
    attachment_polls jsonb,
    mentions_obj jsonb,
    referenced_tweets jsonb,
    user_id text,
    sp_connection_name text,
    sp_ctx jsonb,
    _ctx jsonb
)
SERVER steampipe
OPTIONS (
    "table" 'twitter_user_tweet'
);


ALTER FOREIGN TABLE twitter.twitter_user_tweet OWNER TO root;

--
-- Name: FOREIGN TABLE twitter_user_tweet; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON FOREIGN TABLE twitter.twitter_user_tweet IS 'The user Tweet timeline endpoints provides access to Tweets published by a specific Twitter account.';


--
-- Name: COLUMN twitter_user_tweet.id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.id IS 'Unique identifier of this Tweet.';


--
-- Name: COLUMN twitter_user_tweet.text; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.text IS 'The content of the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.author_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.author_id IS 'Unique identifier of the author of the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.conversation_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.conversation_id IS 'The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).';


--
-- Name: COLUMN twitter_user_tweet.created_at; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.created_at IS 'Creation time of the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.in_reply_to_user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.in_reply_to_user_id IS 'If this Tweet is a Reply, indicates the user ID of the parent Tweet''s author.';


--
-- Name: COLUMN twitter_user_tweet.replied_to; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.replied_to IS 'If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.';


--
-- Name: COLUMN twitter_user_tweet.retweeted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.retweeted IS 'If this Tweet is a Retweet, indicates the ID of the orginal Tweet.';


--
-- Name: COLUMN twitter_user_tweet.quoted; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.quoted IS 'If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.';


--
-- Name: COLUMN twitter_user_tweet.mentions; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.mentions IS 'List of users (e.g. steampipeio) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.hashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.hashtags IS 'List of hashtags (e.g. #sql) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.urls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.urls IS 'List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.cashtags; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.cashtags IS 'List of cashtags (e.g. $TWTR) mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.entities; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.entities IS 'Contains details about text that has a special meaning in a Tweet.';


--
-- Name: COLUMN twitter_user_tweet.attachments; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.attachments IS 'Specifies the type of attachments (if any) present in this Tweet.';


--
-- Name: COLUMN twitter_user_tweet.geo; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.geo IS 'Contains details about the location tagged by the user in this Tweet, if they specified one.';


--
-- Name: COLUMN twitter_user_tweet.context_annotations; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.context_annotations IS 'Contains context annotations for the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.withheld; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.withheld IS 'Contains withholding details for withheld content.';


--
-- Name: COLUMN twitter_user_tweet.public_metrics; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.public_metrics IS 'Engagement metrics for the Tweet at the time of the request.';


--
-- Name: COLUMN twitter_user_tweet.possibly_sensitive; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.possibly_sensitive IS 'Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.';


--
-- Name: COLUMN twitter_user_tweet.lang; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.lang IS 'Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.';


--
-- Name: COLUMN twitter_user_tweet.source; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.source IS 'The name of the app the user Tweeted from.';


--
-- Name: COLUMN twitter_user_tweet.author; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.author IS 'Author of the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.in_reply_user; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.in_reply_user IS 'User the Tweet was in reply to.';


--
-- Name: COLUMN twitter_user_tweet.place; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.place IS 'Place where the Tweet was created.';


--
-- Name: COLUMN twitter_user_tweet.attachment_polls; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.attachment_polls IS 'Polls attached to the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.mentions_obj; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.mentions_obj IS 'Users mentioned in the Tweet.';


--
-- Name: COLUMN twitter_user_tweet.referenced_tweets; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.referenced_tweets IS 'Tweets referenced in this Tweet.';


--
-- Name: COLUMN twitter_user_tweet.user_id; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.user_id IS 'ID of the user the tweets are related to.';


--
-- Name: COLUMN twitter_user_tweet.sp_connection_name; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.sp_connection_name IS 'Steampipe connection name.';


--
-- Name: COLUMN twitter_user_tweet.sp_ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet.sp_ctx IS 'Steampipe context in JSON form.';


--
-- Name: COLUMN twitter_user_tweet._ctx; Type: COMMENT; Schema: twitter; Owner: root
--

COMMENT ON COLUMN twitter.twitter_user_tweet._ctx IS 'Steampipe context in JSON form.';


--
-- Data for Name: steampipe_connection; Type: TABLE DATA; Schema: steampipe_internal; Owner: root
--

COPY steampipe_internal.steampipe_connection (name, state, type, connections, import_schema, error, plugin, plugin_instance, schema_mode, schema_hash, comments_set, connection_mod_time, plugin_mod_time, file_name, start_line_number, end_line_number) FROM stdin;
finance	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/finance@latest	hub.steampipe.io/plugins/turbot/finance@latest	static		t	2025-02-24 15:45:14.40827+00	2025-02-24 15:44:10.838578+00	/home/steampipe/.steampipe/config/finance.spc	1	7
twitter	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/twitter@latest	hub.steampipe.io/plugins/turbot/twitter@latest	static		t	2025-02-24 15:45:14.500446+00	2025-02-24 15:44:19.29456+00	/home/steampipe/.steampipe/config/twitter.spc	1	22
hackernews	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/hackernews@latest	hub.steampipe.io/plugins/turbot/hackernews@latest	static		t	2025-02-24 15:45:14.46315+00	2025-02-24 15:44:28.07854+00	/home/steampipe/.steampipe/config/hackernews.spc	1	8
taptools	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/taptools@latest	hub.steampipe.io/plugins/turbot/taptools@latest	static		t	2025-02-24 15:45:14.471619+00	2025-02-24 15:44:01.258599+00	/home/steampipe/.steampipe/config/taptools.spc	1	4
\.


--
-- Data for Name: steampipe_connection_state; Type: TABLE DATA; Schema: steampipe_internal; Owner: root
--

COPY steampipe_internal.steampipe_connection_state (name, state, type, connections, import_schema, error, plugin, plugin_instance, schema_mode, schema_hash, comments_set, connection_mod_time, plugin_mod_time, file_name, start_line_number, end_line_number) FROM stdin;
finance	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/finance@latest	hub.steampipe.io/plugins/turbot/finance@latest	static		t	2025-02-24 15:45:14.40827+00	2025-02-24 15:44:10.838578+00	/home/steampipe/.steampipe/config/finance.spc	1	7
twitter	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/twitter@latest	hub.steampipe.io/plugins/turbot/twitter@latest	static		t	2025-02-24 15:45:14.500446+00	2025-02-24 15:44:19.29456+00	/home/steampipe/.steampipe/config/twitter.spc	1	22
hackernews	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/hackernews@latest	hub.steampipe.io/plugins/turbot/hackernews@latest	static		t	2025-02-24 15:45:14.46315+00	2025-02-24 15:44:28.07854+00	/home/steampipe/.steampipe/config/hackernews.spc	1	8
taptools	ready	plugin	\N	enabled	\N	hub.steampipe.io/plugins/turbot/taptools@latest	hub.steampipe.io/plugins/turbot/taptools@latest	static		t	2025-02-24 15:45:14.471619+00	2025-02-24 15:44:01.258599+00	/home/steampipe/.steampipe/config/taptools.spc	1	4
\.


--
-- Data for Name: steampipe_plugin; Type: TABLE DATA; Schema: steampipe_internal; Owner: root
--

COPY steampipe_internal.steampipe_plugin (plugin_instance, plugin, version, memory_max_mb, limiters, file_name, start_line_number, end_line_number) FROM stdin;
hub.steampipe.io/plugins/turbot/hackernews@latest	hub.steampipe.io/plugins/turbot/hackernews@latest	1.0.0	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	hub.steampipe.io/plugins/turbot/taptools@latest	local	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	hub.steampipe.io/plugins/turbot/twitter@latest	1.0.0	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	hub.steampipe.io/plugins/turbot/finance@latest	1.0.0	\N	\N	\N	\N	\N
\.


--
-- Data for Name: steampipe_plugin_column; Type: TABLE DATA; Schema: steampipe_internal; Owner: root
--

COPY steampipe_internal.steampipe_plugin_column (plugin, table_name, name, type, description, list_config, get_config, hydrate_name, default_value) FROM stdin;
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	id	STRING	Unique identifier of this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	text	STRING	The content of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	author_id	STRING	Unique identifier of the author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	conversation_id	STRING	The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	created_at	TIMESTAMP	Creation time of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	in_reply_to_user_id	STRING	If this Tweet is a Reply, indicates the user ID of the parent Tweet's author.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	replied_to	STRING	If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	retweeted	STRING	If this Tweet is a Retweet, indicates the ID of the orginal Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	quoted	STRING	If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	mentions	JSON	List of users (e.g. steampipeio) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	hashtags	JSON	List of hashtags (e.g. #sql) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	urls	JSON	List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	cashtags	JSON	List of cashtags (e.g. $TWTR) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	entities	JSON	Contains details about text that has a special meaning in a Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	attachments	JSON	Specifies the type of attachments (if any) present in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	geo	JSON	Contains details about the location tagged by the user in this Tweet, if they specified one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	context_annotations	JSON	Contains context annotations for the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	withheld	JSON	Contains withholding details for withheld content.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	public_metrics	JSON	Engagement metrics for the Tweet at the time of the request.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	possibly_sensitive	BOOL	Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	lang	STRING	Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	source	STRING	The name of the app the user Tweeted from.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	author	JSON	Author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	in_reply_user	JSON	User the Tweet was in reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	place	JSON	Place where the Tweet was created.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	attachment_polls	JSON	Polls attached to the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	mentions_obj	JSON	Users mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	referenced_tweets	JSON	Tweets referenced in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	user_id	STRING	ID of the user the tweets are related to.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	userIDString	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	quoted	STRING	If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_tweet	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	id	STRING	Unique identifier of this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	text	STRING	The content of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	author_id	STRING	Unique identifier of the author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	conversation_id	STRING	The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	created_at	TIMESTAMP	Creation time of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	in_reply_to_user_id	STRING	If this Tweet is a Reply, indicates the user ID of the parent Tweet's author.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	replied_to	STRING	If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	retweeted	STRING	If this Tweet is a Retweet, indicates the ID of the orginal Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	quoted	STRING	If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	mentions	JSON	List of users (e.g. steampipeio) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	hashtags	JSON	List of hashtags (e.g. #sql) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	urls	JSON	List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	cashtags	JSON	List of cashtags (e.g. $TWTR) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	entities	JSON	Contains details about text that has a special meaning in a Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	attachments	JSON	Specifies the type of attachments (if any) present in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	geo	JSON	Contains details about the location tagged by the user in this Tweet, if they specified one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	context_annotations	JSON	Contains context annotations for the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	withheld	JSON	Contains withholding details for withheld content.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	public_metrics	JSON	Engagement metrics for the Tweet at the time of the request.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	possibly_sensitive	BOOL	Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	lang	STRING	Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	source	STRING	The name of the app the user Tweeted from.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	author	JSON	Author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	in_reply_user	JSON	User the Tweet was in reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	place	JSON	Place where the Tweet was created.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	attachment_polls	JSON	Polls attached to the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	mentions_obj	JSON	Users mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	referenced_tweets	JSON	Tweets referenced in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	query	STRING	Query string for the exploit search.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	queryString	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_search_recent	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	id	STRING	Unique identifier of this Tweet.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	text	STRING	The content of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	author_id	STRING	Unique identifier of the author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	conversation_id	STRING	The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	created_at	TIMESTAMP	Creation time of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	in_reply_to_user_id	STRING	If this Tweet is a Reply, indicates the user ID of the parent Tweet's author.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	replied_to	STRING	If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	retweeted	STRING	If this Tweet is a Retweet, indicates the ID of the orginal Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	mentions	JSON	List of users (e.g. steampipeio) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	hashtags	JSON	List of hashtags (e.g. #sql) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	urls	JSON	List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	cashtags	JSON	List of cashtags (e.g. $TWTR) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	entities	JSON	Contains details about text that has a special meaning in a Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	attachments	JSON	Specifies the type of attachments (if any) present in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	geo	JSON	Contains details about the location tagged by the user in this Tweet, if they specified one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	context_annotations	JSON	Contains context annotations for the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	withheld	JSON	Contains withholding details for withheld content.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	public_metrics	JSON	Engagement metrics for the Tweet at the time of the request.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	possibly_sensitive	BOOL	Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	lang	STRING	Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	source	STRING	The name of the app the user Tweeted from.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	author	JSON	Author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	in_reply_user	JSON	User the Tweet was in reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	place	JSON	Place where the Tweet was created.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	attachment_polls	JSON	Polls attached to the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	mentions_obj	JSON	Users mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	referenced_tweets	JSON	Tweets referenced in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_tweet	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	id	STRING	The unique identifier of this user.	{"require": "any_of", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	name	STRING	The name of the user, as they’ve defined it on their profile. Not necessarily a person’s name.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	username	STRING	The Twitter screen name, handle, or alias that this user identifies themselves with. Usernames are unique but subject to change.	{"require": "any_of", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	created_at	TIMESTAMP	The UTC datetime that the user account was created on Twitter.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	description	STRING	The text of this user's profile description (also known as bio), if the user provided one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	entities	JSON	Entities are JSON objects that provide additional information about hashtags, urls, user mentions, and cashtags associated with the description.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	location	STRING	The location specified in the user's profile, if the user provided one. As this is a freeform value, it may not indicate a valid location, but it may be fuzzily evaluated when performing searches with location queries.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	pinned_tweet	JSON	Contains withholding details for withheld content, if applicable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	pinned_tweet_id	STRING	Unique identifier of this user's pinned Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	profile_image_url	STRING	The URL to the profile image for this user, as shown on the user's profile.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	protected	STRING	Indicates if this user has chosen to protect their Tweets (in other words, if this user's Tweets are private).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	public_metrics	JSON	Contains details about activity for this user.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	url	STRING	The URL specified in the user's profile, if present.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	verified	BOOL	Indicates if this user is a verified Twitter User.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	withheld	JSON	Contains withholding details for withheld content, if applicable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	id	STRING	The unique identifier of this user.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	name	STRING	The name of the user, as they’ve defined it on their profile. Not necessarily a person’s name.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	username	STRING	The Twitter screen name, handle, or alias that this user identifies themselves with. Usernames are unique but subject to change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	created_at	TIMESTAMP	The UTC datetime that the user account was created on Twitter.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	description	STRING	The text of this user's profile description (also known as bio), if the user provided one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	entities	JSON	Entities are JSON objects that provide additional information about hashtags, urls, user mentions, and cashtags associated with the description.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	location	STRING	The location specified in the user's profile, if the user provided one. As this is a freeform value, it may not indicate a valid location, but it may be fuzzily evaluated when performing searches with location queries.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	pinned_tweet	JSON	Contains withholding details for withheld content, if applicable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	pinned_tweet_id	STRING	Unique identifier of this user's pinned Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	profile_image_url	STRING	The URL to the profile image for this user, as shown on the user's profile.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	protected	STRING	Indicates if this user has chosen to protect their Tweets (in other words, if this user's Tweets are private).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	public_metrics	JSON	Contains details about activity for this user.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	url	STRING	The URL specified in the user's profile, if present.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	verified	BOOL	Indicates if this user is a verified Twitter User.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	withheld	JSON	Contains withholding details for withheld content, if applicable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	user_id	STRING	ID of the user who is followed by these users.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	userIDString	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_follower	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	id	STRING	The unique identifier of this user.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	name	STRING	The name of the user, as they’ve defined it on their profile. Not necessarily a person’s name.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	username	STRING	The Twitter screen name, handle, or alias that this user identifies themselves with. Usernames are unique but subject to change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	created_at	TIMESTAMP	The UTC datetime that the user account was created on Twitter.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	description	STRING	The text of this user's profile description (also known as bio), if the user provided one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	entities	JSON	Entities are JSON objects that provide additional information about hashtags, urls, user mentions, and cashtags associated with the description.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	location	STRING	The location specified in the user's profile, if the user provided one. As this is a freeform value, it may not indicate a valid location, but it may be fuzzily evaluated when performing searches with location queries.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	pinned_tweet	JSON	Contains withholding details for withheld content, if applicable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	pinned_tweet_id	STRING	Unique identifier of this user's pinned Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	profile_image_url	STRING	The URL to the profile image for this user, as shown on the user's profile.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	protected	STRING	Indicates if this user has chosen to protect their Tweets (in other words, if this user's Tweets are private).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	public_metrics	JSON	Contains details about activity for this user.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	url	STRING	The URL specified in the user's profile, if present.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	verified	BOOL	Indicates if this user is a verified Twitter User.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	withheld	JSON	Contains withholding details for withheld content, if applicable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	user_id	STRING	ID of the user who is followed by these users.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	userIDString	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_following	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	id	STRING	Unique identifier of this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	text	STRING	The content of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	author_id	STRING	Unique identifier of the author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	conversation_id	STRING	The Tweet ID of the original Tweet of the conversation (which includes direct replies, replies of replies).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	created_at	TIMESTAMP	Creation time of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	in_reply_to_user_id	STRING	If this Tweet is a Reply, indicates the user ID of the parent Tweet's author.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	replied_to	STRING	If this Tweet is a Reply, indicates the ID of the Tweet it is a reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	retweeted	STRING	If this Tweet is a Retweet, indicates the ID of the orginal Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	quoted	STRING	If this Tweet is a Quote Tweet, indicates the ID of the original Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	mentions	JSON	List of users (e.g. steampipeio) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	hashtags	JSON	List of hashtags (e.g. #sql) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	urls	JSON	List of URLs (e.g. https://steampipe.io) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	cashtags	JSON	List of cashtags (e.g. $TWTR) mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	entities	JSON	Contains details about text that has a special meaning in a Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	attachments	JSON	Specifies the type of attachments (if any) present in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	geo	JSON	Contains details about the location tagged by the user in this Tweet, if they specified one.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	context_annotations	JSON	Contains context annotations for the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	withheld	JSON	Contains withholding details for withheld content.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	public_metrics	JSON	Engagement metrics for the Tweet at the time of the request.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	possibly_sensitive	BOOL	Indicates if this Tweet contains URLs marked as sensitive, for example content suitable for mature audiences.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	lang	STRING	Language of the Tweet, if detected by Twitter. Returned as a BCP47 language tag.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	source	STRING	The name of the app the user Tweeted from.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	author	JSON	Author of the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	in_reply_user	JSON	User the Tweet was in reply to.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	place	JSON	Place where the Tweet was created.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	attachment_polls	JSON	Polls attached to the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	mentions_obj	JSON	Users mentioned in the Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	referenced_tweets	JSON	Tweets referenced in this Tweet.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	user_id	STRING	ID of the user the tweets are related to.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	userIDString	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/twitter@latest	twitter_user_mention	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	name	STRING	Name of the company.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	symbol	STRING	Symbol of the company.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	cik	STRING	Central Index Key (CIK), if available for the company. The CIK is used to identify entities that are regulated by the Securities and Exchange Commission (SEC).	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	currency	STRING	Currency the symbol is traded in using.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	is_enabled	BOOL	True if the symbol is enabled for trading on IEX.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	date	TIMESTAMP	Date the symbol reference data was generated.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	exchange	STRING	Exchange symbol.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	exchange_name	STRING	Exchange name.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	exchange_segment	STRING	Exchange segment.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	exchange_segment_name	STRING	Exchange segment name.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	exchange_suffix	STRING	Exchange segment suffix.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	figi	STRING	OpenFIGI id for the security, if available.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	iex_id	STRING	Unique ID applied by IEX to track securities through symbol changes.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	lei	STRING	Legal Entity Identifier (LEI) for the security, if available.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	region	STRING	Country code for the symbol.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	type	STRING	common issue typepossible values are: ad - ADR, cs - Common Stock, cef - Closed End Fund, et - ETF, oef - Open Ended Fund, ps - Preferred Stock, rt - Right, struct - Structured Product, ut - Unit, wi - When Issued, wt - Warrant, empty - Other.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_public_company	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	symbol	STRING	Symbol for the filer.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	cik	STRING	CIK (Central Index Key) of the filer.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	name	STRING	Name of the filer.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	sic	STRING	SIC (Standard Industrial Classification) of the filer.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	sic_description	STRING	Description of the SIC (Standard Industrial Classification) of the filer.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_us_sec_filer	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	symbol	STRING	Symbol to quote.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	short_name	STRING	Short descriptive name for the entity.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_price	DOUBLE	Price in the regular market.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_time	TIMESTAMP	Time when the regular market data was updated.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	ask	DOUBLE	Ask price. 	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	ask_size	DOUBLE	Ask size.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	average_daily_volume_10_day	INT	Average daily volume - last 10 days.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	average_daily_volume_3_month	INT	Average daily volume - last 3 months.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	bid	DOUBLE	Bid price.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	bid_size	DOUBLE	Bid size.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	currency_id	STRING	Currency ID, e.g. AUD, USD.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	exchange_id	STRING	Exchange ID, e.g. NYQ, CCC.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	exchange_timezone_name	STRING	Timezone at the exchange.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	exchange_timezone_short_name	STRING	Timezone short name at the exchange.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_day_average	DOUBLE	50 day average price.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_day_average_change	DOUBLE	50 day average change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_day_average_change_percent	DOUBLE	50 day average change percentage.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_two_week_high	DOUBLE	52 week high.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_two_week_high_change	DOUBLE	52 week high change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_two_week_high_change_percent	DOUBLE	52 week high change percentage.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_two_week_low	DOUBLE	52 week low.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_two_week_low_change	DOUBLE	52 week low change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	fifty_two_week_low_change_percent	DOUBLE	52 week low change percent.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	full_exchange_name	STRING	Full exchange name.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	gmt_offset_milliseconds	INT	GMT offset in milliseconds.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	is_tradeable	BOOL	True if the symbol is tradeable.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	market_id	STRING	Market identifier, e.g. us_market.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	market_state	STRING	Current state of the market, e.g. REGULAR, CLOSED.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	post_market_change	DOUBLE	Post market price change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	post_market_change_percent	DOUBLE	Post market price change percentage.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	post_market_price	DOUBLE	Post market price.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	post_market_time	TIMESTAMP	Timestamp for post market data.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	pre_market_change	DOUBLE	Pre market price change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	pre_market_change_percent	DOUBLE	Pre market price change percentage.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	pre_market_price	DOUBLE	Pre market price.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	pre_market_time	TIMESTAMP	Timestamp for pre market data.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	quote_delay	INT	Quote delay in minutes.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	quote_source	STRING	Quote source.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	quote_type	STRING	Quote type, e.g. EQUITY, CRYPTOCURRENCY.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_change	DOUBLE	Change in price since the regular market open.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_change_percent	DOUBLE	Change percentage during the regular market session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_day_high	DOUBLE	High price for the regular market day.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_day_low	DOUBLE	Low price for the regular market day.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_open	DOUBLE	Opening price for the regular market.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_previous_close	DOUBLE	Close price of the previous regular market session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	regular_market_volume	INT	Trading volume for the regular market session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	source_interval	INT	Source interval in minutes.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	two_hundred_day_average	DOUBLE	200 day average price.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	two_hundred_day_average_change	DOUBLE	200 day average price change.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	two_hundred_day_average_change_percent	DOUBLE	200 day average price change percentage.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	symbol	STRING	Symbol to quote.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	symbolString	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	adjusted_close	DOUBLE	Adjusted close price after accounting for any corporate actions.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	close	DOUBLE	Last price during the regular trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	high	DOUBLE	Highest price during the trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	low	DOUBLE	Lowest price during the trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	open	DOUBLE	Opening price during the trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	timestamp	TIMESTAMP	Timestamp of the record.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	volume	INT	Total trading volume (units bought and sold) during the period.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_daily	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	symbol	STRING	Symbol to quote.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	symbolString	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	adjusted_close	DOUBLE	Adjusted close price after accounting for any corporate actions.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	close	DOUBLE	Last price during the regular trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	high	DOUBLE	Highest price during the trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	low	DOUBLE	Lowest price during the trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	open	DOUBLE	Opening price during the trading session.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	timestamp	TIMESTAMP	Timestamp of the record.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	volume	INT	Total trading volume (units bought and sold) during the period.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/finance@latest	finance_quote_hourly	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_show_hn	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_top	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	id	STRING	The user's unique username. Case-sensitive. Required.	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	created	STRING	Creation timestamp of the user.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	karma	INT	The user's karma.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	about	STRING	The user's optional self-description. HTML.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	submitted	JSON	List of the user's stories, polls and comments.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_user	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_ask_hn	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_best	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_item	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_job	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	id	INT	The item's unique id.	\N	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	title	STRING	The title of the story, poll or job. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	time	TIMESTAMP	Timestamp when the item was created.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	by	STRING	The username of the item's author.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	score	INT	The story's score, or the votes for a pollopt.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	dead	BOOL	True if the item is dead.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	deleted	BOOL	True if the item is deleted.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	descendants	INT	In the case of stories or polls, the total comment count.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	kids	JSON	The ids of the item's comments, in ranked display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	parent	INT	The comment's parent: either another comment or the relevant story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	parts	JSON	A list of related pollopts, in display order.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	poll	INT	The pollopt's associated poll.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	text	STRING	The comment, story or poll text. HTML.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	type	STRING	The type of item. One of "job", "story", "comment", "poll", or "pollopt".	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	url	STRING	The URL of the story.	\N	\N	getItem	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/hackernews@latest	hackernews_new	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	circ_supply	DOUBLE	Circulating supply of the token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	fdv	DOUBLE	Fully diluted valuation of the token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	mcap	DOUBLE	Market cap of the token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	price	DOUBLE	Current price of the token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	ticker	STRING	Ticker symbol of the token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	total_supply	DOUBLE	Total supply of the token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	sellers	INT	Number of unique sellers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_market_cap	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	avg_sale	DOUBLE	Average sale price	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	fees	DOUBLE	Total fees collected	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	liquidity	DOUBLE	Liquidity in the marketplace	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	listings	INT	Number of current listings	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	name	STRING	Name of the marketplace	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	royalties	DOUBLE	Total royalties paid	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	sales	INT	Number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	users	INT	Number of unique users	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	volume	DOUBLE	Total trading volume	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	timeframe	STRING	Example: timeframe=30d The time interval. Options are 24h, 7d, 30d, 90d, 180d, all. Defaults to 7d.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	marketplace	STRING	Example: marketplace=jpg.store Filters data to a certain marketplace by name.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	last_day	INT	Example: lastDay=0 Filters to only count data that occurred between yesterday 00:00UTC and today 00:00UTC (0,1).	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_marketplace_stats	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	address	STRING	Address of the holder	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	amount	INT	Number of NFTs held by the address	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	per_page	INT	Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	exclude_exchanges	INT	Example: excludeExchanges=1 Whether or not to exclude marketplace addresses (0, 1)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_holders	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	collateral_amount	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	collateral_token	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	collateral_value	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	debt_amount	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	debt_token	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	debt_value	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	duration	INT	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	hash	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	health	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	interest_amount	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	interest_token	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	interest_value	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	protocol	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	time	INT	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	sells	INT	Number of sell transactions	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name) to filter by	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	include	STRING	Example: include=collateral,debt Comma separated value enabling you to filter to offers where token is used as collateral, debt, interest or a mix of them, default is collateral,debt filtering to offers where token is used as collateral OR debt.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	sort_by	STRING	Example: sortBy=time What should the results be sorted by. Options are time, duration. Default is time. duration is loan duration in seconds.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	order	STRING	Example: order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	per_page	INT	Example: perPage=100 Specify how many items to return per page, default is 100.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_loan_offers	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	listings	INT	Number of current listings for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	listings_pct_chg	DOUBLE	Percentage change in listings	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	owners	INT	Number of unique owners	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	owners_pct_chg	DOUBLE	Percentage change in owners	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	price	DOUBLE	Current floor price of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	price_pct_chg	DOUBLE	Percentage change in price	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	sales	DOUBLE	Total number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	sales_pct_chg	DOUBLE	Percentage change in sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	top_offer	DOUBLE	Highest offer currently on the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	volume	DOUBLE	Lifetime trading volume of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	volume_pct_chg	DOUBLE	Percentage change in volume	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	timeframe	STRING	Example: timeframe=24h The time interval. Options are 24h, 7d, 30d. Defaults to 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats_extended	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	close	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	high	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	low	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	open	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	volume	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	onchain_id	STRING	Example: onchainID=0be55d262b29f564998ff81efe21bdc0022621c12f15af08d0f2ddb1.39b9b709ac8605fc82116a2efc308181ba297c11950f0f350001e28f0e50868b Pair onchain ID to get ohlc data for	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	interval	STRING	Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	num_intervals	INT	Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_ohlcv	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	buyers	INT	Number of unique buyers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	sales	INT	Total number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	sellers	INT	Number of unique sellers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	volume	DOUBLE	Trading volume within the specified timeframe	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	timeframe	STRING	Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trading_stats	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	close	DOUBLE	Closing price for the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	high	DOUBLE	Highest price during the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	low	DOUBLE	Lowest price during the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	open	DOUBLE	Opening price for the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	time	INT	Unix timestamp at the start of the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	volume	DOUBLE	Volume of trades during the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	interval	STRING	Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	num_intervals	INT	Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_floor_price_ohlcv	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	listings	INT	Number of current listings for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	listings_pct_chg	DOUBLE	Percentage change in listings	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	logo	STRING	URL of the collection's logo	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	name	STRING	Name of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	owners	INT	Number of unique owners	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	owners_pct_chg	DOUBLE	Percentage change in owners	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	policy	STRING	Policy ID of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	price	DOUBLE	Current price of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	price_pct_chg	DOUBLE	Percentage change in price	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	sales	INT	Number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	sales_pct_chg	DOUBLE	Percentage change in sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	volume	DOUBLE	Trading volume of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	volume_pct_chg	DOUBLE	Percentage change in volume	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	timeframe	STRING	Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	per_page	INT	Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections_extended	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	description	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	discord	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	email	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	facebook	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	github	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	instagram	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	medium	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	reddit	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	telegram	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	twitter	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	website	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	youtube	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_links	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	price	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	ticker	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	unit	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	volume	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	timeframe	STRING	The timeframe in which to aggregate data.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	per_page	INT	Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_volume	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	address	STRING	The address of the token holder	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	amount	DOUBLE	The amount of tokens held by this address	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	per_page	INT	Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_holders	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	buy_volume	DOUBLE	Total volume of buys	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	buyers	INT	Number of unique buyers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	buys	INT	Number of buy transactions	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	sell_volume	DOUBLE	Total volume of sells	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	timeframe	STRING	Example: timeframe=24h Specify a timeframe in which to aggregate the data by. Options are [15m, 1h, 4h, 12h, 24h, 7d, 30d, 90d, 180d, 1y, all]. Default is 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trading_stats	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_prices	token	STRING	The token unit (policy + hex name)	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_prices	price	DOUBLE	The current price of the token aggregated across supported DEXs	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_prices	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_prices	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_prices	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	listings	INT	Number of current listings for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	owners	INT	Number of unique owners	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	price	DOUBLE	Current floor price of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	sales	DOUBLE	Total number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	top_offer	DOUBLE	Highest offer currently on the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	volume	DOUBLE	Lifetime trading volume of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_stats	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_quote_price	price	DOUBLE	Current price of the quote currency	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_quote_price	quote	STRING	Example: quote=USD Quote currency to use (USD, EUR, ETH, BTC). Default is USD.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_quote_price	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_quote_price	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_quote_price	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_available_quote_currencies	currency	STRING	Available quote currency	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_available_quote_currencies	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_available_quote_currencies	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_available_quote_currencies	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	listings	INT	Number of current listings for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	logo	STRING	URL of the collection's logo	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	name	STRING	Name of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	policy	STRING	Policy ID of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	price	DOUBLE	Current price of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	sales	INT	Number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	volume	DOUBLE	Trading volume of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	timeframe	STRING	Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	per_page	INT	Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_top_volume_collections	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	circSupply	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	fdv	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	mcap	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	price	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	ticker	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	totalSupply	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	unit	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	type	STRING	Example: type=mcap Sort tokens by circulating market cap or fully diluted value. Options [mcap, fdv].	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	per_page	INT	Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_mcap	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	action	STRING	Action of the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	address	STRING	Address involved in the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	exchange	STRING	Exchange where the trade occurred	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	hash	STRING	Hash of the trade transaction	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	lp_token_unit	STRING	Unit of the liquidity pool token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	price	DOUBLE	Price of the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	time	INT	Unix timestamp of the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	token_a	STRING	Token A in the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	token_a_amount	DOUBLE	Amount of token A traded	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	token_a_name	STRING	Name of token A	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	token_b	STRING	Token B in the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	token_b_amount	DOUBLE	Amount of token B traded	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	token_b_name	STRING	Name of token B	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	timeframe	STRING	Example: timeframe=30d The time interval. Options are 1h, 4h, 24h, 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	sort_by	STRING	Example: sortBy=amount What should the results be sorted by. Options are amount, time. Default is amount. Filters to only ADA trades if set to amount.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	sort_order	STRING	Example: sort_order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	unit	STRING	Example: unit=279c909f348e533da5808898f87f9a14bb2c3dfbbacccd631d927a3f534e454b Optionally filter to a specific token by specifying a token unit (policy + hex name).	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	min_amount	INT	Example: minAmount=1000 Filter to only trades of a certain ADA amount.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	from_timestamp	INT	Example: from_timestamp=1704759422 Filter trades using a UNIX timestamp, will only return trades after this timestamp.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	per_page	INT	Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_trades	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	holders	INT	Number of holders at this time point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	time	INT	Unix timestamp for the data point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	timeframe	STRING	Example: timeframe=30d The time interval. Options are 7d, 30d, 90d, 180d, 1y and all. Defaults to 30d.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_trended_holders	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	buyer_address	STRING	Address of the buyer	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	collection_name	STRING	Name of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	hash	STRING	Transaction hash of the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	image	STRING	URL of the NFT's image	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	market	STRING	Marketplace where the trade occurred	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	name	STRING	Name of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	policy	STRING	Policy ID of the collection	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	price	DOUBLE	Price of the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	seller_address	STRING	Address of the seller	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	time	INT	Unix timestamp of the trade	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	timeframe	STRING	Example: timeframe=30d The time interval. Options are 1h, 4h, 24h, 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	sort_by	STRING	Example: sortBy=time What should the results be sorted by. Options are amount, time. Default is time.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	order_by	STRING	Example: order_by=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	min_amount	INT	Example: min_amount=1000 Filter to only trades of a certain ADA amount.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	from_timestamp	INT	Example: from_timestamp=1704759422 Filter trades using a UNIX timestamp, will only return trades after this timestamp.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	per_page	INT	Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_trades	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	exchange	STRING	The exchange where the liquidity pool is	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	lp_token_unit	STRING	Unit of the liquidity pool token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	token_a	STRING	Unit of token A in the pool	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	token_a_locked	DOUBLE	Amount of token A locked in the pool	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	token_a_ticker	STRING	Ticker for token A	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	token_b	STRING	Unit of token B in the pool	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	token_b_locked	DOUBLE	Amount of token B locked in the pool	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	token_b_ticker	STRING	Ticker for token B	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	buyer_stake_address	STRING	Buyer's stake address	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	onchain_id	STRING	Example: onchainID=0be55d262b29f564998ff81efe21bdc0022621c12f15af08d0f2ddb1.39b9b709ac8605fc82116a2efc308181ba297c11950f0f350001e28f0e50868b Liquidity pool onchainID	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	ada_only	INT	Example: adaOnly=1 Return only ADA pools or all pools (0, 1)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_liquidity_pools	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	collateral_amount	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	collateral_token	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	collateral_value	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	debt_amount	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	debt_token	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	debt_value	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	expiration	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	hash	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	health	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	interest_amount	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	interest_token	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	interest_value	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	protocol	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	time	INT	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	include	STRING	Example: include=collateral,debt Comma separated value enabling you to filter to loans where token is used as collateral, debt, interest or a mix of them, default is collateral,debt filtering to loans where token is used as collateral OR debt.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	sort_by	STRING	Example: sortBy=time What should the results be sorted by. Options are time, expiration. Default is time. expiration is expiration date of loan.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	sort_order	STRING	Example: sort_order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	per_page	INT	Example: perPage=100 Specify how many items to return per page, default is 100.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_active_loans	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	category	STRING	The category of the trait	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	trait	STRING	The specific trait within the category	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	price	DOUBLE	The floor price of the trait	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	name	STRING	Example: name=ClayNation3725 The name of a specific NFT to get trait prices for.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_trait_prices	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	price	DOUBLE	Sale price of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	seller_stake_address	STRING	Seller's stake address	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	time	INT	Unix timestamp of the sale	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	name	STRING	Example: name=ClayNation3725 The name of a specific NFT to get stats for.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_history	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	price	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	ticker	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	unit	STRING	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	liquidity	DOUBLE	\N	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	per_page	INT	Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_top_liquidity	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	category	STRING	The category of the metadata attribute (e.g., Accessories, Background)	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	attribute	STRING	The specific attribute within the category (e.g., Bowtie, Cyan)	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	probability	DOUBLE	The probability of occurrence for this attribute (e.g., 0.0709)	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	policy	STRING	The policy ID for the collection. Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e	{"require": "required", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_metadata_rarity	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	value	DOUBLE	The indicator value	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	interval	STRING	Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	items	INT	Example: items=100 The number of items to return. The maximum number of items that can be returned is 1000.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	indicator	STRING	Example: indicator=ma Specify which indicator to use. Options are ma, ema, rsi, macd, bb, bbw.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	length	INT	Example: length=14 Length of data to include. Used in ma, ema, rsi, bb, and bbw.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	smoothing_factor	INT	Example: smoothingFactor=2 Length of data to include for smoothing. Used in ema. Most often is set to 2.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	fast_length	INT	Example: fastLength=12 Length of shorter EMA to use in MACD. Only used in macd	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	slow_length	INT	Example: slowLength=26 Length of longer EMA to use in MACD. Only used in macd	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	signal_length	INT	Example: signalLength=9 Length of signal EMA to use in MACD. Only used in macd	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	std_mult	INT	Example: stdMult=2 Standard deviation multiplier to use for upper and lower bands of Bollinger Bands (typically set to 2). Used in bb and bbw.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	quote	STRING	Example: quote=ADA Which quote currency to use when building price data (e.g. ADA, USD).	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_indicators	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	is_listed	BOOL	Whether the NFT is currently listed for sale	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	last_listed_price	DOUBLE	The price at which the NFT was last listed	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	last_listed_time	INT	Unix timestamp when the NFT was last listed	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	last_sold_price	DOUBLE	The price at which the NFT was last sold	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	last_sold_time	INT	Unix timestamp when the NFT was last sold	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	owners	DOUBLE	Number of unique owners of this NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	sales	DOUBLE	Total number of sales for this NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	times_listed	DOUBLE	Number of times this NFT has been listed	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	volume	DOUBLE	Total trading volume of this NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	name	STRING	Example: name=ClayNation3725 The name of a specific NFT to get stats for.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_stats	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_holders	holders	INT	Total number of holders for the specified token	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_holders	unit	STRING	Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_holders	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_holders	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_holders	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	image	STRING	URL of the NFT image	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	name	STRING	Name of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	price	DOUBLE	Current price of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	rank	INT	Rank of the NFT within the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	sort_by	STRING	Example: sortBy=price What should the results be sorted by. Options are price and rank. Default is price.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	order_by	STRING	Example: order_by=asc Which direction should the results be sorted. Options are asc, desc. Default is asc	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	search	STRING	Example: search=ClayNation3725 Search for a certain NFT's name, default is null.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	on_sale	STRING	Example: onSale=1 Return only nfts that are on sale Options are 0, 1. Default is 0.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	per_page	INT	Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_assets	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	one	INT	Number of holders with exactly 1 NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	two_to_four	INT	Number of holders with 2 to 4 NFTs	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	five_to_nine	INT	Number of holders with 5 to 9 NFTs	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	ten_to_twenty_four	INT	Number of holders with 10 to 24 NFTs	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	twenty_five_plus	INT	Number of holders with 25 or more NFTs	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_holder_distribution	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	rank	INT	Rank of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	trait_category	STRING	Category of the trait	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	trait_name	STRING	Name of the trait	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	trait_price	DOUBLE	Price of the trait	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	trait_rarity	DOUBLE	Rarity of the trait	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	policy	STRING	The policy ID for the collection. Example: 40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	name	STRING	The name of a specific NFT to get stats for. Example: ClayNation3725	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	prices	STRING	Whether to include trait prices (0 or 1). Default is 1. Example: 0	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_traits	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	avg	DOUBLE	Average price of NFTs at this price point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	count	INT	Number of listings at this price point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	price	DOUBLE	Price point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	total	DOUBLE	Total value of NFTs listed at this price point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	items	INT	Example: items=600 Specify how many items to return. Maximum is 1000, default is 500.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_depth	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	addresses	INT	Count of unique addresses that have engaged in NFT transactions	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	buyers	INT	Number of unique buyers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	sales	INT	Total number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	sellers	INT	Number of unique sellers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	volume	DOUBLE	Total trading volume	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	timeframe	STRING	Example: timeframe=1d The time interval. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	listings	INT	Number of listings at this time point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	price	DOUBLE	Floor price at this time point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	time	INT	Unix timestamp for the data point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	interval	STRING	Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	num_intervals	INT	Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here. Leave blank for full history.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_listings_trended	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_market_volume_trended	time	INT	Unix timestamp for the data point	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_market_volume_trended	value	DOUBLE	Volume of NFT market transactions for this timeframe	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_market_volume_trended	timeframe	STRING	Example: timeframe=30d The time interval. Options are 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_market_volume_trended	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_market_volume_trended	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_market_volume_trended	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	price	DOUBLE	Average price for the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	sales	INT	Number of sales during the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	time	INT	Unix timestamp at the start of the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	volume	DOUBLE	Volume of trades during the interval	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	interval	STRING	Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	num_intervals	INT	Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here. Leave blank for full history.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_volume_trended	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings	listings	INT	Number of active listings in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	description	STRING	Description of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	discord	STRING	Discord server link for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	logo	STRING	URL of the collection's logo	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	name	STRING	Name of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	twitter	STRING	Twitter handle for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	website	STRING	Official website of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_collection_info	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	image	STRING	URL of the NFT's image	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	market	STRING	Marketplace where the NFT is listed	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	name	STRING	Name of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	price	DOUBLE	Current listing price of the NFT	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	time	INT	Unix timestamp when the NFT was listed	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	policy	STRING	Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	sort_by	STRING	Example: sortBy=price What should the results be sorted by. Options are price, time. Default is price.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	order_by	STRING	Example: order_by=asc Which direction should the results be sorted. Options are asc, desc. Default is asc	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	page	INT	Example: page=1 This endpoint supports pagination. Default page is 1.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	per_page	INT	Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_active_listings_individual	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_rarity_rank	rank	INT	Rarity rank of the NFT within its collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_rarity_rank	policy	STRING	Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_rarity_rank	name	STRING	Example: name=ClayNation3725 The name of the NFT	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_rarity_rank	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_rarity_rank	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_rarity_rank	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	unit	STRING	Token unit (policy + hex name)	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	timeframe	STRING	Timeframe for which the percent change is calculated	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	percent_change	DOUBLE	Percent change in price for the specified timeframe	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	timeframes	STRING	Example: timeframes=1h,4h,24h,7d,30d List of timeframes	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_token_price_percent_change	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	addresses	INT	Count of unique addresses that have engaged in NFT transactions	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	addresses_pct_chg	DOUBLE	Percentage change in addresses	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	buyers	INT	Number of unique buyers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	buyers_pct_chg	DOUBLE	Percentage change in buyers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	sales	INT	Total number of sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	sales_pct_chg	DOUBLE	Percentage change in sales	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	sellers	INT	Number of unique sellers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	sellers_pct_chg	DOUBLE	Percentage change in sellers	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	volume	DOUBLE	Total trading volume	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	volume_pct_chg	DOUBLE	Percentage change in volume	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	timeframe	STRING	Example: timeframe=1d The time interval. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_market_wide_nft_stats_extended	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	listings	INT	Number of listings for the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	logo	STRING	URL of the collection's logo	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	market_cap	DOUBLE	Market capitalization of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	name	STRING	Name of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	policy	STRING	Policy ID of the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	price	DOUBLE	Current price	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	price_24h_chg	DOUBLE	Price change in the last 24 hours	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	price_30d_chg	DOUBLE	Price change in the last 30 days	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	price_7d_chg	DOUBLE	Price change in the last 7 days	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	rank	INT	Ranking based on specified criteria	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	supply	INT	Total supply of NFTs in the collection	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	volume_24h	DOUBLE	Volume traded in the last 24 hours	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	volume_24h_chg	DOUBLE	Volume change in the last 24 hours	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	volume_30d	DOUBLE	Volume traded in the last 30 days	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	volume_30d_chg	DOUBLE	Volume change in the last 30 days	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	volume_7d	DOUBLE	Volume traded in the last 7 days	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	volume_7d_chg	DOUBLE	Volume change in the last 7 days	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	ranking	STRING	Example: ranking=marketCap Criteria to rank NFT Collections based on. Options are marketCap, volume, gainers, losers.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	items	INT	Example: items=50 Specify how many items to return. Maximum is 100, default is 25.	{"require": "optional", "operators": ["="], "cache_match": "subset"}	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	sp_connection_name	STRING	Steampipe connection name.	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	{"require": "optional", "operators": ["=", "!=", "~~", "~~*", "!~~", "!~~*"]}	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	sp_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
hub.steampipe.io/plugins/turbot/taptools@latest	taptools_nft_top_rankings	_ctx	JSON	Steampipe context in JSON form.	\N	\N	\N	\N
\.


--
-- Data for Name: steampipe_plugin_limiter; Type: TABLE DATA; Schema: steampipe_internal; Owner: root
--

COPY steampipe_internal.steampipe_plugin_limiter (name, plugin, plugin_instance, source_type, status, bucket_size, fill_rate, max_concurrency, scope, "where", file_name, start_line_number, end_line_number) FROM stdin;
\.


--
-- Data for Name: steampipe_server_settings; Type: TABLE DATA; Schema: steampipe_internal; Owner: root
--

COPY steampipe_internal.steampipe_server_settings (start_time, steampipe_version, fdw_version, cache_max_ttl, cache_max_size_mb, cache_enabled) FROM stdin;
2025-02-24 15:45:14.135983+00	1.0.3	1.12.2	300	0	t
\.


--
-- Name: steampipe_connection steampipe_connection_pkey; Type: CONSTRAINT; Schema: steampipe_internal; Owner: root
--

ALTER TABLE ONLY steampipe_internal.steampipe_connection
    ADD CONSTRAINT steampipe_connection_pkey PRIMARY KEY (name);


--
-- Name: steampipe_connection_state steampipe_connection_state_pkey; Type: CONSTRAINT; Schema: steampipe_internal; Owner: root
--

ALTER TABLE ONLY steampipe_internal.steampipe_connection_state
    ADD CONSTRAINT steampipe_connection_state_pkey PRIMARY KEY (name);


--
-- Name: SCHEMA finance; Type: ACL; Schema: -; Owner: root
--

GRANT USAGE ON SCHEMA finance TO steampipe_users;


--
-- Name: SCHEMA hackernews; Type: ACL; Schema: -; Owner: root
--

GRANT USAGE ON SCHEMA hackernews TO steampipe_users;


--
-- Name: SCHEMA steampipe_command; Type: ACL; Schema: -; Owner: root
--

GRANT USAGE ON SCHEMA steampipe_command TO steampipe_users;


--
-- Name: SCHEMA steampipe_internal; Type: ACL; Schema: -; Owner: root
--

GRANT USAGE ON SCHEMA steampipe_internal TO steampipe_users;


--
-- Name: SCHEMA taptools; Type: ACL; Schema: -; Owner: root
--

GRANT USAGE ON SCHEMA taptools TO steampipe_users;


--
-- Name: SCHEMA twitter; Type: ACL; Schema: -; Owner: root
--

GRANT USAGE ON SCHEMA twitter TO steampipe_users;


--
-- Name: TABLE finance_quote; Type: ACL; Schema: finance; Owner: root
--

GRANT SELECT ON TABLE finance.finance_quote TO steampipe_users;


--
-- Name: TABLE finance_quote_daily; Type: ACL; Schema: finance; Owner: root
--

GRANT SELECT ON TABLE finance.finance_quote_daily TO steampipe_users;


--
-- Name: TABLE finance_quote_hourly; Type: ACL; Schema: finance; Owner: root
--

GRANT SELECT ON TABLE finance.finance_quote_hourly TO steampipe_users;


--
-- Name: TABLE finance_us_sec_filer; Type: ACL; Schema: finance; Owner: root
--

GRANT SELECT ON TABLE finance.finance_us_sec_filer TO steampipe_users;


--
-- Name: TABLE finance_us_sec_public_company; Type: ACL; Schema: finance; Owner: root
--

GRANT SELECT ON TABLE finance.finance_us_sec_public_company TO steampipe_users;


--
-- Name: TABLE hackernews_ask_hn; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_ask_hn TO steampipe_users;


--
-- Name: TABLE hackernews_best; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_best TO steampipe_users;


--
-- Name: TABLE hackernews_item; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_item TO steampipe_users;


--
-- Name: TABLE hackernews_job; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_job TO steampipe_users;


--
-- Name: TABLE hackernews_new; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_new TO steampipe_users;


--
-- Name: TABLE hackernews_show_hn; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_show_hn TO steampipe_users;


--
-- Name: TABLE hackernews_top; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_top TO steampipe_users;


--
-- Name: TABLE hackernews_user; Type: ACL; Schema: hackernews; Owner: root
--

GRANT SELECT ON TABLE hackernews.hackernews_user TO steampipe_users;


--
-- Name: TABLE cache; Type: ACL; Schema: steampipe_command; Owner: root
--

GRANT INSERT ON TABLE steampipe_command.cache TO steampipe_users;


--
-- Name: TABLE scan_metadata; Type: ACL; Schema: steampipe_command; Owner: root
--

GRANT SELECT ON TABLE steampipe_command.scan_metadata TO steampipe_users;


--
-- Name: TABLE steampipe_connection; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_connection TO steampipe_users;


--
-- Name: TABLE steampipe_connection_state; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_connection_state TO steampipe_users;


--
-- Name: TABLE steampipe_plugin; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_plugin TO steampipe_users;


--
-- Name: TABLE steampipe_plugin_column; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_plugin_column TO steampipe_users;


--
-- Name: TABLE steampipe_plugin_limiter; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_plugin_limiter TO steampipe_users;


--
-- Name: TABLE steampipe_scan_metadata; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_scan_metadata TO steampipe_users;


--
-- Name: TABLE steampipe_scan_metadata_summary; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_scan_metadata_summary TO steampipe_users;


--
-- Name: TABLE steampipe_server_settings; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT SELECT ON TABLE steampipe_internal.steampipe_server_settings TO steampipe_users;


--
-- Name: TABLE steampipe_settings; Type: ACL; Schema: steampipe_internal; Owner: root
--

GRANT INSERT ON TABLE steampipe_internal.steampipe_settings TO steampipe_users;


--
-- Name: TABLE taptools_active_listings; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_active_listings TO steampipe_users;


--
-- Name: TABLE taptools_active_listings_individual; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_active_listings_individual TO steampipe_users;


--
-- Name: TABLE taptools_available_quote_currencies; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_available_quote_currencies TO steampipe_users;


--
-- Name: TABLE taptools_collection_assets; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_collection_assets TO steampipe_users;


--
-- Name: TABLE taptools_collection_info; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_collection_info TO steampipe_users;


--
-- Name: TABLE taptools_collection_metadata_rarity; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_collection_metadata_rarity TO steampipe_users;


--
-- Name: TABLE taptools_collection_stats; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_collection_stats TO steampipe_users;


--
-- Name: TABLE taptools_collection_stats_extended; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_collection_stats_extended TO steampipe_users;


--
-- Name: TABLE taptools_collection_trait_prices; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_collection_trait_prices TO steampipe_users;


--
-- Name: TABLE taptools_holder_distribution; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_holder_distribution TO steampipe_users;


--
-- Name: TABLE taptools_market_wide_nft_stats; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_market_wide_nft_stats TO steampipe_users;


--
-- Name: TABLE taptools_market_wide_nft_stats_extended; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_market_wide_nft_stats_extended TO steampipe_users;


--
-- Name: TABLE taptools_nft_floor_price_ohlcv; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_floor_price_ohlcv TO steampipe_users;


--
-- Name: TABLE taptools_nft_history; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_history TO steampipe_users;


--
-- Name: TABLE taptools_nft_listings_depth; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_listings_depth TO steampipe_users;


--
-- Name: TABLE taptools_nft_listings_trended; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_listings_trended TO steampipe_users;


--
-- Name: TABLE taptools_nft_market_volume_trended; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_market_volume_trended TO steampipe_users;


--
-- Name: TABLE taptools_nft_marketplace_stats; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_marketplace_stats TO steampipe_users;


--
-- Name: TABLE taptools_nft_rarity_rank; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_rarity_rank TO steampipe_users;


--
-- Name: TABLE taptools_nft_stats; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_stats TO steampipe_users;


--
-- Name: TABLE taptools_nft_top_rankings; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_top_rankings TO steampipe_users;


--
-- Name: TABLE taptools_nft_trades; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_trades TO steampipe_users;


--
-- Name: TABLE taptools_nft_trading_stats; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_trading_stats TO steampipe_users;


--
-- Name: TABLE taptools_nft_traits; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_traits TO steampipe_users;


--
-- Name: TABLE taptools_nft_volume_trended; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_nft_volume_trended TO steampipe_users;


--
-- Name: TABLE taptools_quote_price; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_quote_price TO steampipe_users;


--
-- Name: TABLE taptools_token_active_loans; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_active_loans TO steampipe_users;


--
-- Name: TABLE taptools_token_holders; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_holders TO steampipe_users;


--
-- Name: TABLE taptools_token_links; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_links TO steampipe_users;


--
-- Name: TABLE taptools_token_liquidity_pools; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_liquidity_pools TO steampipe_users;


--
-- Name: TABLE taptools_token_loan_offers; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_loan_offers TO steampipe_users;


--
-- Name: TABLE taptools_token_market_cap; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_market_cap TO steampipe_users;


--
-- Name: TABLE taptools_token_price_indicators; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_price_indicators TO steampipe_users;


--
-- Name: TABLE taptools_token_price_ohlcv; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_price_ohlcv TO steampipe_users;


--
-- Name: TABLE taptools_token_price_percent_change; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_price_percent_change TO steampipe_users;


--
-- Name: TABLE taptools_token_prices; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_prices TO steampipe_users;


--
-- Name: TABLE taptools_token_top_holders; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_top_holders TO steampipe_users;


--
-- Name: TABLE taptools_token_top_liquidity; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_top_liquidity TO steampipe_users;


--
-- Name: TABLE taptools_token_top_mcap; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_top_mcap TO steampipe_users;


--
-- Name: TABLE taptools_token_top_volume; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_top_volume TO steampipe_users;


--
-- Name: TABLE taptools_token_trades; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_token_trades TO steampipe_users;


--
-- Name: TABLE taptools_top_holders; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_top_holders TO steampipe_users;


--
-- Name: TABLE taptools_top_volume_collections; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_top_volume_collections TO steampipe_users;


--
-- Name: TABLE taptools_top_volume_collections_extended; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_top_volume_collections_extended TO steampipe_users;


--
-- Name: TABLE taptools_trading_stats; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_trading_stats TO steampipe_users;


--
-- Name: TABLE taptools_trended_holders; Type: ACL; Schema: taptools; Owner: root
--

GRANT SELECT ON TABLE taptools.taptools_trended_holders TO steampipe_users;


--
-- Name: TABLE twitter_search_recent; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_search_recent TO steampipe_users;


--
-- Name: TABLE twitter_tweet; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_tweet TO steampipe_users;


--
-- Name: TABLE twitter_user; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_user TO steampipe_users;


--
-- Name: TABLE twitter_user_follower; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_user_follower TO steampipe_users;


--
-- Name: TABLE twitter_user_following; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_user_following TO steampipe_users;


--
-- Name: TABLE twitter_user_mention; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_user_mention TO steampipe_users;


--
-- Name: TABLE twitter_user_tweet; Type: ACL; Schema: twitter; Owner: root
--

GRANT SELECT ON TABLE twitter.twitter_user_tweet TO steampipe_users;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: finance; Owner: root
--

ALTER DEFAULT PRIVILEGES FOR ROLE root IN SCHEMA finance GRANT SELECT ON TABLES  TO steampipe_users;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: hackernews; Owner: root
--

ALTER DEFAULT PRIVILEGES FOR ROLE root IN SCHEMA hackernews GRANT SELECT ON TABLES  TO steampipe_users;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: taptools; Owner: root
--

ALTER DEFAULT PRIVILEGES FOR ROLE root IN SCHEMA taptools GRANT SELECT ON TABLES  TO steampipe_users;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: twitter; Owner: root
--

ALTER DEFAULT PRIVILEGES FOR ROLE root IN SCHEMA twitter GRANT SELECT ON TABLES  TO steampipe_users;


--
-- PostgreSQL database dump complete
--

