package taptools

import (
	"context"
	"fmt"
	"io"

	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

func tableTaptoolsTokenPriceOhlcv() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_price_ohlcv",
		Description: "Get a specific token's trended (open, high, low, close, volume) price data. You can either pass a token unit to get aggregated data across all liquidity pools, or an onchainID for a specific pair (see /token/pools).",
		List: &plugin.ListConfig{
			Hydrate: listTokenPriceOhlcv,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "onchain_id", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "interval", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "num_intervals", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "close", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "high", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "low", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "open", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Description: ""},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
			{Name: "onchain_id", Type: proto.ColumnType_STRING, Transform: transform.FromField("OnchainId"), Description: "Example: onchainID=0be55d262b29f564998ff81efe21bdc0022621c12f15af08d0f2ddb1.39b9b709ac8605fc82116a2efc308181ba297c11950f0f350001e28f0e50868b Pair onchain ID to get ohlc data for"},
			{Name: "interval", Type: proto.ColumnType_STRING, Transform: transform.FromField("Interval"), Description: "Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M."},
			{Name: "num_intervals", Type: proto.ColumnType_INT, Transform: transform.FromField("NumIntervals"), Description: "Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here."},
		},
	}
}

// Define a struct to hold the response from the API
type TokenPriceOhlcvResponseItem struct {
	Open         float64 `json:"open"`
	High         float64 `json:"high"`
	Low          float64 `json:"low"`
	Close        float64 `json:"close"`
	Volume       float64 `json:"volume"`
	Unit         string  `json:"unit,omitempty"`
	OnchainId    string  `json:"onchainId,omitempty"`
	Interval     string  `json:"interval"`
	NumIntervals int64   `json:"numIntervals"`
}

func listTokenPriceOhlcv(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Default values
	var unit, onchainId string
	interval := "1d"
	numIntervals := int64(10)

	// Get query parameters from the query context
	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["onchain_id"]; quals != nil && len(quals.Quals) > 0 {
		onchainId = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["interval"]; quals != nil && len(quals.Quals) > 0 {
		interval = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["num_intervals"]; quals != nil && len(quals.Quals) > 0 {
		numIntervals = quals.Quals[0].Value.GetInt64Value()
	}

	// Ensure unit and onchainId are mutually exclusive
	if unit != "" && onchainId != "" {
		return nil, fmt.Errorf("unit and onchain_id cannot both be provided")
	}

	// Check if at least one of unit or onchainId is provided
	if unit == "" && onchainId == "" {
		return nil, fmt.Errorf("either unit or onchain_id must be provided")
	}

	// Check if the timeframe is valid (you might need to adjust based on API documentation)
	validIntervals := map[string]bool{
		"3m":  true,
		"5m":  true,
		"15m": true,
		"30m": true,
		"1h":  true,
		"2h":  true,
		"4h":  true,
		"12h": true,
		"1d":  true,
		"3d":  true,
		"1w":  true,
		"1M":  true}
	if !validIntervals[interval] {
		log.Printf("Invalid interval '%s' provided, defaulting to '1d'", interval)
		interval = "1d"
	}

	var reqUrl string
	// URL for the API endpoint with proper escaping
	if unit != "" {
		reqUrl = fmt.Sprintf("https://openapi.taptools.io/api/v1/token/ohlcv?unit=%s&interval=%s&numIntervals=%d", unit, interval, numIntervals)
	} else {
		reqUrl = fmt.Sprintf("https://openapi.taptools.io/api/v1/token/ohlcv?onchainID=%s&interval=%s&numIntervals=%d", onchainId, interval, numIntervals)
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
	var apiResponse []struct {
		Open   float64 `json:"open"`
		High   float64 `json:"high"`
		Low    float64 `json:"low"`
		Close  float64 `json:"close"`
		Volume float64 `json:"volume"`
	}
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TokenPriceOhlcvResponseItem{
			Open:         item.Open,
			High:         item.High,
			Low:          item.Low,
			Close:        item.Close,
			Volume:       item.Volume,
			Unit:         unit,
			OnchainId:    onchainId,
			Interval:     interval,
			NumIntervals: numIntervals,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			return nil, nil
		}
	}

	return nil, nil
}
