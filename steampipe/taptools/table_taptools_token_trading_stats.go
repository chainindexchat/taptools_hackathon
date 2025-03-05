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
type TradingStatsResponse struct {
	BuyVolume  float64 `json:"buyVolume"`
	Buyers     int64   `json:"buyers"`
	Buys       int64   `json:"buys"`
	SellVolume float64 `json:"sellVolume"`
	Sellers    int64   `json:"sellers"`
	Sells      int64   `json:"sells"`

	Unit      string `json:"unit,omitempty"`
	Timeframe string `json:"timeframe,omitempty"`
}

func listTradingStats(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var unit, timeframe string

	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
	}

	// Check if unit is provided
	if unit == "" {
		return nil, fmt.Errorf("unit must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/trading/stats?unit=%s", unit)
	if timeframe != "" {
		reqUrl += "&timeframe=" + timeframe
	}

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
		body, _ := io.ReadAll(res.Body) // read the error body for debugging
		return nil, fmt.Errorf("API returned non-200 status: %d, body: %s", res.StatusCode, string(body))
	}

	// Read the response body
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("error reading response body: %v", err)
	}

	// Decode JSON response
	var apiResponse TradingStatsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the unit and timeframe metadata
	d.StreamListItem(ctx, TradingStatsResponse{
		BuyVolume:  apiResponse.BuyVolume,
		Buyers:     apiResponse.Buyers,
		Buys:       apiResponse.Buys,
		SellVolume: apiResponse.SellVolume,
		Sellers:    apiResponse.Sellers,
		Sells:      apiResponse.Sells,
		Unit:       unit,
		Timeframe:  timeframe,
	})

	return nil, nil
}

func tableTaptoolsTradingStats() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_trading_stats",
		Description: "Get aggregated trading stats for a particular token.",
		List: &plugin.ListConfig{
			Hydrate: listTradingStats,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "buy_volume", Type: proto.ColumnType_DOUBLE, Description: "Total volume of buys"},
			{Name: "buyers", Type: proto.ColumnType_INT, Description: "Number of unique buyers"},
			{Name: "buys", Type: proto.ColumnType_INT, Description: "Number of buy transactions"},
			{Name: "sell_volume", Type: proto.ColumnType_DOUBLE, Description: "Total volume of sells"},
			{Name: "sellers", Type: proto.ColumnType_INT, Description: "Number of unique sellers"},
			{Name: "sells", Type: proto.ColumnType_INT, Description: "Number of sell transactions"},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=24h Specify a timeframe in which to aggregate the data by. Options are [15m, 1h, 4h, 12h, 24h, 7d, 30d, 90d, 180d, 1y, all]. Default is 24h."},
		},
	}
}
