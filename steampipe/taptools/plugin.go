package taptools

import (
	"context"

	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

func Plugin(ctx context.Context) *plugin.Plugin {
	p := &plugin.Plugin{
		Name:             "steampipe-plugin-taptools",
		DefaultTransform: transform.FromGo().NullIfZero(),
		TableMap: map[string]*plugin.Table{
			// NFT related tables
			"taptools_active_listings_individual":      tableTaptoolsActiveListingsIndividual(),
			"taptools_active_listings":                 tableTaptoolsActiveListings(),
			"taptools_collection_assets":               tableTaptoolsCollectionAssets(),
			"taptools_collection_info":                 tableTaptoolsCollectionInfo(),
			"taptools_collection_metadata_rarity":      tableTaptoolsCollectionMetadataRarity(),
			"taptools_collection_stats_extended":       tableTaptoolsCollectionStatsExtended(),
			"taptools_collection_stats":                tableTaptoolsCollectionStats(),
			"taptools_collection_trait_prices":         tableTaptoolsCollectionTraitPrices(),
			"taptools_nft_floor_price_ohlcv":           tableTaptoolsNFTFloorPriceOHLCV(),
			"taptools_holder_distribution":             tableTaptoolsHolderDistribution(),
			"taptools_nft_listings_depth":              tableTaptoolsNFTListingsDepth(),
			"taptools_nft_listings_trended":            tableTaptoolsNFTListingsTrended(),
			"taptools_nft_market_volume_trended":       tableTaptoolsNFTMarketVolumeTrended(),
			"taptools_market_wide_nft_stats_extended":  tableTaptoolsMarketWideNFTStatsExtended(),
			"taptools_market_wide_nft_stats":           tableTaptoolsMarketWideNFTStats(),
			"taptools_nft_marketplace_stats":           tableTaptoolsNFTMarketplaceStats(),
			"taptools_nft_rarity_rank":                 tableTaptoolsNFTRarityRank(),
			"taptools_nft_history":                     tableTaptoolsNFTHistory(),
			"taptools_nft_stats":                       tableTaptoolsNFTStats(),
			"taptools_top_holders":                     tableTaptoolsTopHolders(),
			"taptools_nft_top_rankings":                tableTaptoolsNFTTopRankings(),
			"taptools_top_volume_collections_extended": tableTaptoolsTopVolumeCollectionsExtended(),
			"taptools_top_volume_collections":          tableTaptoolsTopVolumeCollections(),
			"taptools_nft_trades":                      tableTaptoolsNFTTrades(),
			"taptools_nft_trading_stats":               tableTaptoolsNFTTradingStats(),
			"taptools_nft_traits":                      tableTaptoolsNFTTraits(),
			"taptools_trended_holders":                 tableTaptoolsTrendedHolders(),
			"taptools_nft_volume_trended":              tableTaptoolsNFTVolumeTrended(),

			// Token related tables
			"taptools_token_active_loans":         tableTaptoolsTokenActiveLoans(),
			"taptools_available_quote_currencies": tableTaptoolsAvailableQuoteCurrencies(),
			"taptools_token_holders":              tableTaptoolsTokenHolders(),
			"taptools_token_links":                tableTaptoolsTokenLinks(),
			"taptools_token_liquidity_pools":      tableTaptoolsTokenLiquidityPools(),
			"taptools_token_loan_offers":          tableTaptoolsTokenLoanOffers(),
			"taptools_token_market_cap":           tableTaptoolsTokenMarketCap(),
			"taptools_token_price_indicators":     tableTaptoolsTokenPriceIndicators(),
			"taptools_token_price_ohlcv":          tableTaptoolsTokenPriceOhlcv(),
			"taptools_token_price_percent_change": tableTaptoolsTokenPricePercentChange(),
			"taptools_token_prices":               tableTaptoolsTokenPrices(),
			"taptools_quote_price":                tableTaptoolsQuotePrice(),
			"taptools_token_top_holders":          tableTaptoolsTokenTopHolders(),
			"taptools_token_top_liquidity":        tableTaptoolsTokenTopLiquidity(),
			"taptools_token_top_mcap":             tableTaptoolsTokenTopMcap(),
			"taptools_token_top_volume":           tableTaptoolsTokenTopVolume(),
			"taptools_token_trades":               tableTaptoolsTokenTrades(),
			"taptools_trading_stats":              tableTaptoolsTradingStats(),
		},
	}
	return p
}
