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
type TokenMarketCapResponse struct {
	CircSupply  float64 `json:"circSupply"`
	Fdv         float64 `json:"fdv"`
	Mcap        float64 `json:"mcap"`
	Price       float64 `json:"price"`
	Ticker      string  `json:"ticker"`
	TotalSupply float64 `json:"totalSupply"`
	Unit        string  `json:"unit,omitempty"`
}

func listTokenMarketCap(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var unit string
	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}

	// Check if unit is provided
	if unit == "" {
		return nil, fmt.Errorf("unit must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/mcap?unit=%s", unit)

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
	var apiResponse TokenMarketCapResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the unit metadata
	d.StreamListItem(ctx, TokenMarketCapResponse{
		CircSupply:  apiResponse.CircSupply,
		Fdv:         apiResponse.Fdv,
		Mcap:        apiResponse.Mcap,
		Price:       apiResponse.Price,
		Ticker:      apiResponse.Ticker,
		TotalSupply: apiResponse.TotalSupply,
		Unit:        unit,
	})

	return nil, nil
}

func tableTaptoolsTokenMarketCap() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_market_cap",
		Description: "Get a specific token's supply and market cap information.",
		List: &plugin.ListConfig{
			Hydrate: listTokenMarketCap,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "circ_supply", Type: proto.ColumnType_DOUBLE, Description: "Circulating supply of the token"},
			{Name: "fdv", Type: proto.ColumnType_DOUBLE, Description: "Fully diluted valuation of the token"},
			{Name: "mcap", Type: proto.ColumnType_DOUBLE, Description: "Market cap of the token"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current price of the token"},
			{Name: "ticker", Type: proto.ColumnType_STRING, Description: "Ticker symbol of the token"},
			{Name: "total_supply", Type: proto.ColumnType_DOUBLE, Description: "Total supply of the token"},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
		},
	}
}
