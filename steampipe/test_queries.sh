steampipe query "SELECT * FROM taptools_token_price_ohlcv WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND interval = 'test' AND num_intervals = 1;"
steampipe query "SELECT * FROM taptools_token_links WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441';"
steampipe query "SELECT * FROM taptools_token_active_loans WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND include = 'collateral,debt' AND sort_by = 'time' AND sort_order = 'desc' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_token_holders WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441';"
steampipe query "SELECT * FROM taptools_top_token_holders WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_token_price_indicators WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND interval = '1d' AND items = 1 AND indicator = 'rsi' AND length = 14 AND smoothing_factor = 2 AND fast_length = 12 AND slow_length = 26 AND signal_length = 9 AND std_mult = 2 AND quote = 'ADA';"
steampipe query "SELECT * FROM taptools_token_market_cap WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441';"
steampipe query "SELECT * FROM taptools_token_liquidity_pools WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND ada_only = 1;"
steampipe query "SELECT * FROM taptools_token_price_percent_change WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND timeframes = '1h';"
steampipe query "SELECT * FROM taptools_quote_price WHERE quote = 'USD';"
steampipe query "SELECT * FROM taptools_token_trades WHERE timeframe = '1h' AND sort_by = 'time' AND sort_order = 'asc' AND unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND min_amount = 1000 AND from_timestamp = 1740148872 AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_trading_stats WHERE unit = '8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441' AND timeframe = '1h';"
steampipe query "SELECT * FROM taptools_nft_history WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND name = 'ClayNation3725';"
steampipe query "SELECT * FROM taptools_nft_stats WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND name = 'ClayNation3725';"
steampipe query "SELECT * FROM taptools_nft_traits WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND name = 'ClayNation3725' AND prices = '0';"
steampipe query "SELECT * FROM taptools_collection_assets WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND sort_by = 'price' AND order_by = 'asc' AND search = 'ClayNation3725' AND on_sale = '0' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_holder_distribution WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728';"
steampipe query "SELECT * FROM taptools_top_holders WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND page = 1 AND per_page = 1 AND exclude_exchanges = 1;"
steampipe query "SELECT * FROM taptools_trended_holders WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND timeframe = '7d';"
steampipe query "SELECT * FROM taptools_collection_info WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e';"
steampipe query "SELECT * FROM taptools_active_listings WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e';"
steampipe query "SELECT * FROM taptools_nft_listings_depth WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND items = 1;"
steampipe query "SELECT * FROM taptools_active_listings_individual WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND sort_by = 'price' AND order_by = 'asc' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_nft_listings_trended WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND interval = '1d' AND num_intervals = 1;"
steampipe query "SELECT * FROM taptools_nft_floor_price_ohlcv WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND interval = '1d' AND num_intervals = 1;"
steampipe query "SELECT * FROM taptools_collection_stats WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e';"
steampipe query "SELECT * FROM taptools_collection_stats_extended WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND timeframe = '24h';"
steampipe query "SELECT * FROM taptools_nft_trades WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND timeframe = '1h' AND sort_by = 'time' AND order_by = 'asc' AND min_amount = 1000 AND from_timestamp = 1740148872 AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_nft_trades WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND sort_by = 'time' AND order_by = 'asc' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_nft_trading_stats WHERE policy = '1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e' AND timeframe = '24h';"
steampipe query "SELECT * FROM taptools_collection_trait_prices WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND name = 'ClayNation3725';"
steampipe query "SELECT * FROM taptools_collection_metadata_rarity WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728';"
steampipe query "SELECT * FROM taptools_nft_rarity_rank WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND name = 'ClayNation3725';"
steampipe query "SELECT * FROM taptools_nft_volume_trended WHERE policy = '40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728' AND interval = '3m' AND num_intervals = 1;"
steampipe query "SELECT * FROM taptools_market_wide_nft_stats WHERE timeframe = '1h';"
steampipe query "SELECT * FROM taptools_market_wide_nft_stats_extended WHERE timeframe = '1h';"
steampipe query "SELECT * FROM taptools_nft_market_volume_trended WHERE timeframe = '7d';"
steampipe query "SELECT * FROM taptools_nft_marketplace_stats WHERE timeframe = '24h' AND marketplace = 'jpg.store' AND last_day = 1;"
steampipe query "SELECT * FROM taptools_nft_top_rankings WHERE ranking = 'volume' AND items = 1;"
steampipe query "SELECT * FROM taptools_top_volume_collections WHERE timeframe = '24h' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_top_volume_collections_extended WHERE timeframe = '24h' AND page = 1 AND per_page = 1;"
steampipe query "SELECT * FROM taptools_token_top_volume WHERE timeframe = '1y' AND page = 1 AND per_page = 100;"
SELECT * FROM taptools_token_top_volume WHERE timeframe = '1y' AND page = 1 AND per_page = 100;
SELECT jsonb_pretty(json_agg(row_to_json(t))::jsonb) AS result
FROM (
    SELECT 
        v.ticker,
        v.unit,
        l.description,
        l.twitter  
    FROM taptools_token_top_volume v
    LEFT JOIN taptools_token_links l ON v.unit = l.unit
    WHERE v.timeframe = '1y' AND v.page = 1 AND v.per_page = 100
) t;