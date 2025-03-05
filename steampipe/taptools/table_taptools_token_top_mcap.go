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

func tableTaptoolsTokenTopMcap() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_top_mcap",
		Description: "Get tokens with top market cap in a descending order. This endpoint does exclude deprecated tokens (e.g. MELD V1 since there was a token migration to MELD V2).",
		List: &plugin.ListConfig{
			Hydrate: listTokenTopMcap,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "type", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "circSupply", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "fdv", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "mcap", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "ticker", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "totalSupply", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "unit", Type: proto.ColumnType_STRING, Description: ""},
			// Query parameters
			{Name: "type", Type: proto.ColumnType_STRING, Transform: transform.FromField("Type"), Description: "Example: type=mcap Sort tokens by circulating market cap or fully diluted value. Options [mcap, fdv]."},
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20."},
		},
	}
}

// Define a struct to hold the response from the API
type TokenMcapResponseItem struct {
	CircSupply  float64 `json:"circSupply"`
	Fdv         float64 `json:"fdv"`
	Mcap        float64 `json:"mcap"`
	Price       float64 `json:"price"`
	Ticker      string  `json:"ticker"`
	TotalSupply float64 `json:"totalSupply"`
	Unit        string  `json:"unit"`
	Type        string  `json:"type"`
	Page        int64   `json:"page"`
	PerPage     int64   `json:"perPage"`
}

func listTokenTopMcap(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	page := int64(1)
	perPage := int64(20)
	Type := "mcap" // Default to 24h

	var reqUrl string
	// Default values
	// Get query parameters from the query context
	if quals := d.Quals["type"]; quals != nil {
		for _, q := range quals.Quals {
			if q.Operator == "=" {
				Type = q.Value.GetStringValue()
			}
		}
	}
	if quals := d.Quals["page"]; quals != nil {
		for _, q := range quals.Quals {
			if q.Operator == "=" {
				page = q.Value.GetInt64Value()
			}
		}
	}
	if quals := d.Quals["per_page"]; quals != nil {
		for _, q := range quals.Quals {
			if q.Operator == "=" {
				perPage = q.Value.GetInt64Value()
			}
		}
	}

	// Ensure positive page number and per page
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 { // Assuming there's a maximum limit of 100 items per page by the API
		perPage = 20
	}

	// Check if the timeframe is valid (you might need to adjust based on API documentation)
	validTypes := map[string]bool{"mcap": true, "fdv": true}
	if !validTypes[Type] {
		log.Printf("Invalid Type '%s' provided, defaulting to 'mcap'", Type)
		Type = "mcap" // fallback to a known valid timeframe
	}

	// URL for the API endpoint with proper escaping
	reqUrl = fmt.Sprintf("https://openapi.taptools.io/api/v1/token/top/mcap?timeframe=%s&page=%d&perPage=%d",
		Type, page, perPage)

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
		CircSupply  float64 `json:"circSupply"`
		Fdv         float64 `json:"fdv"`
		Mcap        float64 `json:"mcap"`
		Price       float64 `json:"price"`
		Ticker      string  `json:"ticker"`
		TotalSupply float64 `json:"totalSupply"`
		Unit        string  `json:"unit"`
	}
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TokenMcapResponseItem{
			CircSupply:  item.CircSupply,
			Fdv:         item.Fdv,
			Mcap:        item.Mcap,
			Price:       item.Price,
			Ticker:      item.Ticker,
			TotalSupply: item.TotalSupply,
			Unit:        item.Unit,
			Page:        page,
			PerPage:     perPage,
			Type:        Type,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			return nil, nil
		}
	}

	return nil, nil
}
