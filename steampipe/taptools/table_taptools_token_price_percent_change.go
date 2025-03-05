package taptools

import (
	"context"
	"fmt"
	"io"
	"strings"

	"encoding/json"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

// Table definition
func tableTaptoolsTokenPricePercentChange() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_price_percent_change",
		Description: "Get a specific token's price percent change over various timeframes.",
		List: &plugin.ListConfig{
			Hydrate: listTokenPricePercentChange,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "timeframes", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("unit"), Description: "Token unit (policy + hex name)"},
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("timeframe"), Description: "Timeframe for which the percent change is calculated"},
			{Name: "percent_change", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("percent_change"), Description: "Percent change in price for the specified timeframe"},
			// Query parameters
			{Name: "timeframes", Type: proto.ColumnType_STRING, Transform: transform.FromField("timeframes"), Description: "Example: timeframes=1h,4h,24h,7d,30d List of timeframes"},
		},
	}
}

// Hydrate function
func listTokenPricePercentChange(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
	// Get API key from environment
	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Extract query parameters
	var unit, timeframes string
	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["timeframes"]; quals != nil && len(quals.Quals) > 0 {
		timeframes = quals.Quals[0].Value.GetStringValue()
	}

	if unit == "" {
		return nil, fmt.Errorf("unit must be provided")
	}

	// Build API request URL
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/prices/chg?unit=%s", unit)
	if timeframes != "" {
		reqUrl += "&timeframes=" + timeframes
	}

	// Create and execute HTTP request
	client := &http.Client{}
	req, err := http.NewRequest("GET", reqUrl, nil)
	if err != nil {
		return nil, fmt.Errorf("error creating request: %v", err)
	}
	req.Header.Add("X-API-Key", TAPTOOLS_API_KEY)

	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("error executing request: %v", err)
	}
	defer res.Body.Close()

	// Check response status
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(res.Body)
		return nil, fmt.Errorf("API returned non-200 status: %d, body: %s", res.StatusCode, string(body))
	}

	// Read and parse response body
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("error reading response body: %v", err)
	}

	var apiResponse map[string]float64
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Determine timeframes to process
	var tfs []string
	if timeframes != "" {
		tfs = strings.Split(timeframes, ",")
	} else {
		for tf := range apiResponse {
			tfs = append(tfs, tf)
		}
	}

	// Stream one row per timeframe
	for _, tf := range tfs {
		if value, exists := apiResponse[tf]; exists {
			d.StreamListItem(ctx, map[string]interface{}{
				"unit":           unit,
				"timeframe":      tf,
				"percent_change": value,
				"timeframes":     timeframes,
			})
		}
	}

	return nil, nil
}
