#!/bin/bash

# Function to generate a steampipe query command for a given table and its key columns
generate_query() {
    table=$1
    keys=$2
    if [ -z "$keys" ]; then
        # If no key columns are provided, generate a simple SELECT with LIMIT 1
        echo "steampipe query \"SELECT * FROM $table LIMIT 1;\""
    else
        # Construct the WHERE clause with all key columns
        query="SELECT * FROM $table WHERE "
        IFS=',' read -ra key_array <<< "$keys"
        for i in "${!key_array[@]}"; do
            key=${key_array[$i]}
            if [ $i -gt 0 ]; then
                query+=" AND "
            fi
            # Use 1 for integer-like parameters, 'test' for others
            if [[ $key == *"page"* || $key == *"per_page"* || $key == *"num_intervals"* || $key == *"items"* || $key == *"last_day"* ]]; then
                query+="$key = 1"
            else
                query+="$key = 'test'"
            fi
        done
        query+=";"
        echo "steampipe query \"$query\"" >> test_queries.sh
    fi
}

echo "Generating Steampipe query commands for all tables..."

# Token-related tables
generate_query "taptools_token_price_ohlcv" "unit,interval,num_intervals"
generate_query "taptools_token_links" "unit"
generate_query "taptools_token_active_loans" "unit,include,sort_by,order,page,per_page"
generate_query "taptools_token_holders" "unit"
generate_query "taptools_top_token_holders" "unit,page,per_page"
generate_query "taptools_token_price_indicators" "unit,interval,items,indicator,length,smoothing_factor,fast_length,slow_length,signal_length,std_mult,quote"
generate_query "taptools_token_market_cap" "unit"
generate_query "taptools_token_liquidity_pools" "unit,onchain_id,ada_only"
generate_query "taptools_token_prices" ""
generate_query "taptools_token_price_percent_change" "unit,timeframes"
generate_query "taptools_quote_price" "quote"
generate_query "taptools_available_quote_currencies" ""
generate_query "taptools_token_trades" "timeframe,sort_by,order,unit,min_amount,from,page,per_page"
generate_query "taptools_trading_stats" "unit,timeframe"

# NFT-related tables
generate_query "taptools_nft_history" "policy,name"
generate_query "taptools_nft_stats" "policy,name"
generate_query "taptools_nft_traits" "policy,name,prices"
generate_query "taptools_collection_assets" "policy,sort_by,order,search,on_sale,page,per_page"
generate_query "taptools_holder_distribution" "policy"
generate_query "taptools_top_holders" "policy,page,per_page,exclude_exchanges"
generate_query "taptools_trended_holders" "policy,timeframe"
generate_query "taptools_collection_info" "policy"
generate_query "taptools_active_listings" "policy"
generate_query "taptools_nft_listings_depth" "policy,items"
generate_query "taptools_active_listings_individual" "policy,sort_by,order,page,per_page"
generate_query "taptools_nft_listings_trended" "policy,interval,num_intervals"
generate_query "taptools_nft_floor_price_ohlcv" "policy,interval,num_intervals"
generate_query "taptools_collection_stats" "policy"
generate_query "taptools_collection_stats_extended" "policy,timeframe"
generate_query "taptools_nft_trades" "policy,timeframe,sort_by,order,min_amount,from,page,per_page"
generate_query "taptools_nft_trading_stats" "policy,timeframe"
generate_query "taptools_collection_trait_prices" "policy,name"
generate_query "taptools_collection_metadata_rarity" "policy"
generate_query "taptools_nft_rarity_rank" "policy,name"
generate_query "taptools_nft_volume_trended" "policy,interval,num_intervals"
generate_query "taptools_market_wide_nft_stats" "timeframe"
generate_query "taptools_market_wide_nft_stats_extended" "timeframe"
generate_query "taptools_nft_market_volume_trended" "timeframe"
generate_query "taptools_nft_marketplace_stats" "timeframe,marketplace,last_day"
generate_query "taptools_nft_top_rankings" "ranking,items"
generate_query "taptools_top_volume_collections" "timeframe,page,per_page"
generate_query "taptools_top_volume_collections_extended" "timeframe,page,per_page"

echo "All query commands generated."