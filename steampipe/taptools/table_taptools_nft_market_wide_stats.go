package taptools

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

// Define the structure for the API response
type MarketWideNFTStatsResponse struct {
	Addresses int64   `json:"addresses"`
	Buyers    int64   `json:"buyers"`
	Sales     int64   `json:"sales"`
	Sellers   int64   `json:"sellers"`
	Volume    float64 `json:"volume"`

	Timeframe string `json:"timeframe,omitempty"`
}

func listMarketWideNFTStats(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var timeframe string

	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
	}

	// Check if timeframe is provided
	if timeframe == "" {
		return nil, fmt.Errorf("timeframe must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/market/stats?timeframe=%s", timeframe)

	// Create HTTP client
	client := &http.Client{}
	req, err := http.NewRequest("GET", reqUrl, nil)
	if err != nil {
		return nil, fmt.Errorf("error creating request: %v", err)
	}
	req.Header.Add("X-API-Key", TAPTOOLS_API_KEY)

	// Execute the request
	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("error executing request: %v", err)
	}
	defer res.Body.Close()

	// Check if the response status is OK or handle specific error codes
	if res.StatusCode != http.StatusOK {
		switch res.StatusCode {
		case http.StatusBadRequest:
			return nil, fmt.Errorf("bad request")
		case http.StatusUnauthorized:
			return nil, fmt.Errorf("not authorized")
		case http.StatusTooManyRequests:
			return nil, fmt.Errorf("rate limit exceeded")
		case http.StatusInternalServerError:
			return nil, fmt.Errorf("interval server error")
		default:
			body, _ := io.ReadAll(res.Body)
			return nil, fmt.Errorf("API returned non-200 status: %d, body: %s", res.StatusCode, string(body))
		}
	}

	// Read the response body
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("error reading response body: %v", err)
	}

	// Decode JSON response
	var apiResponse MarketWideNFTStatsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the timeframe metadata
	d.StreamListItem(ctx, MarketWideNFTStatsResponse{
		Addresses: apiResponse.Addresses,
		Buyers:    apiResponse.Buyers,
		Sales:     apiResponse.Sales,
		Sellers:   apiResponse.Sellers,
		Volume:    apiResponse.Volume,
		Timeframe: timeframe,
	})

	return nil, nil
}

func tableTaptoolsMarketWideNFTStats() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_market_wide_nft_stats",
		Description: "Get high-level market stats across the entire NFT market.",
		List: &plugin.ListConfig{
			Hydrate: listMarketWideNFTStats,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "addresses", Type: proto.ColumnType_INT, Description: "Count of unique addresses that have engaged in NFT transactions"},
			{Name: "buyers", Type: proto.ColumnType_INT, Description: "Number of unique buyers"},
			{Name: "sales", Type: proto.ColumnType_INT, Description: "Total number of sales"},
			{Name: "sellers", Type: proto.ColumnType_INT, Description: "Number of unique sellers"},
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Description: "Total trading volume"},

			// Query parameters
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=1d The time interval. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h."},
		},
	}
}
