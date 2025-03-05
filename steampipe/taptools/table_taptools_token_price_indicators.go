package taptools

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

// Define the structure for the API response
type TokenPriceIndicatorsResponse struct {
	Value float64 `json:"integer"` // Assuming 'integer' in the API doc is a typo for actual value

	Unit            string `json:"unit,omitempty"`
	Interval        string `json:"interval,omitempty"`
	Items           int64  `json:"items,omitempty"`
	Indicator       string `json:"indicator,omitempty"`
	Length          int64  `json:"length,omitempty"`
	SmoothingFactor int64  `json:"smoothingFactor,omitempty"`
	FastLength      int64  `json:"fastLength,omitempty"`
	SlowLength      int64  `json:"slowLength,omitempty"`
	SignalLength    int64  `json:"signalLength,omitempty"`
	StdMult         int64  `json:"stdMult,omitempty"`
	Quote           string `json:"quote,omitempty"`
}

func listTokenPriceIndicators(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var unit, interval, indicator, quote string
	var items, length, smoothingFactor, fastLength, slowLength, signalLength, stdMult int64

	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["interval"]; quals != nil && len(quals.Quals) > 0 {
		interval = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["items"]; quals != nil && len(quals.Quals) > 0 {
		items = quals.Quals[0].Value.GetInt64Value()
		if items > 1000 {
			items = 1000 // Max items is 1000
		}
	}
	if quals := d.Quals["indicator"]; quals != nil && len(quals.Quals) > 0 {
		indicator = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["length"]; quals != nil && len(quals.Quals) > 0 {
		length = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["smoothing_factor"]; quals != nil && len(quals.Quals) > 0 {
		smoothingFactor = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["fast_length"]; quals != nil && len(quals.Quals) > 0 {
		fastLength = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["slow_length"]; quals != nil && len(quals.Quals) > 0 {
		slowLength = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["signal_length"]; quals != nil && len(quals.Quals) > 0 {
		signalLength = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["std_mult"]; quals != nil && len(quals.Quals) > 0 {
		stdMult = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["quote"]; quals != nil && len(quals.Quals) > 0 {
		quote = quals.Quals[0].Value.GetStringValue()
	}

	// Check if unit and interval are provided
	if unit == "" || interval == "" {
		return nil, fmt.Errorf("unit and interval must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/indicators?unit=%s&interval=%s", unit, interval)
	if items != 0 {
		reqUrl += "&items=" + strconv.FormatInt(items, 10)
	}
	if indicator != "" {
		reqUrl += "&indicator=" + indicator
	}
	if length != 0 {
		reqUrl += "&length=" + strconv.FormatInt(length, 10)
	}
	if smoothingFactor != 0 {
		reqUrl += "&smoothingFactor=" + strconv.FormatInt(smoothingFactor, 10)
	}
	if fastLength != 0 {
		reqUrl += "&fastLength=" + strconv.FormatInt(fastLength, 10)
	}
	if slowLength != 0 {
		reqUrl += "&slowLength=" + strconv.FormatInt(slowLength, 10)
	}
	if signalLength != 0 {
		reqUrl += "&signalLength=" + strconv.FormatInt(signalLength, 10)
	}
	if stdMult != 0 {
		reqUrl += "&stdMult=" + strconv.FormatInt(stdMult, 10)
	}
	if quote != "" {
		reqUrl += "&quote=" + quote
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
	var apiResponse []float64 // Assuming the response is an array of float64 values
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, val := range apiResponse {
		d.StreamListItem(ctx, TokenPriceIndicatorsResponse{
			Value:           val,
			Unit:            unit,
			Interval:        interval,
			Items:           items,
			Indicator:       indicator,
			Length:          length,
			SmoothingFactor: smoothingFactor,
			FastLength:      fastLength,
			SlowLength:      slowLength,
			SignalLength:    signalLength,
			StdMult:         stdMult,
			Quote:           quote,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsTokenPriceIndicators() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_price_indicators",
		Description: "Get indicator values (e.g. EMA, RSI) based on price data for a specific token.",
		List: &plugin.ListConfig{
			Hydrate: listTokenPriceIndicators,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "interval", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "items", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "indicator", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "length", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "smoothing_factor", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "fast_length", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "slow_length", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "signal_length", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "std_mult", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "quote", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "value", Type: proto.ColumnType_DOUBLE, Description: "The indicator value"},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
			{Name: "interval", Type: proto.ColumnType_STRING, Transform: transform.FromField("Interval"), Description: "Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M."},
			{Name: "items", Type: proto.ColumnType_INT, Transform: transform.FromField("Items"), Description: "Example: items=100 The number of items to return. The maximum number of items that can be returned is 1000."},
			{Name: "indicator", Type: proto.ColumnType_STRING, Transform: transform.FromField("Indicator"), Description: "Example: indicator=ma Specify which indicator to use. Options are ma, ema, rsi, macd, bb, bbw."},
			{Name: "length", Type: proto.ColumnType_INT, Transform: transform.FromField("Length"), Description: "Example: length=14 Length of data to include. Used in ma, ema, rsi, bb, and bbw."},
			{Name: "smoothing_factor", Type: proto.ColumnType_INT, Transform: transform.FromField("SmoothingFactor"), Description: "Example: smoothingFactor=2 Length of data to include for smoothing. Used in ema. Most often is set to 2."},
			{Name: "fast_length", Type: proto.ColumnType_INT, Transform: transform.FromField("FastLength"), Description: "Example: fastLength=12 Length of shorter EMA to use in MACD. Only used in macd"},
			{Name: "slow_length", Type: proto.ColumnType_INT, Transform: transform.FromField("SlowLength"), Description: "Example: slowLength=26 Length of longer EMA to use in MACD. Only used in macd"},
			{Name: "signal_length", Type: proto.ColumnType_INT, Transform: transform.FromField("SignalLength"), Description: "Example: signalLength=9 Length of signal EMA to use in MACD. Only used in macd"},
			{Name: "std_mult", Type: proto.ColumnType_INT, Transform: transform.FromField("StdMult"), Description: "Example: stdMult=2 Standard deviation multiplier to use for upper and lower bands of Bollinger Bands (typically set to 2). Used in bb and bbw."},
			{Name: "quote", Type: proto.ColumnType_STRING, Transform: transform.FromField("Quote"), Description: "Example: quote=ADA Which quote currency to use when building price data (e.g. ADA, USD)."},
		},
	}
}
