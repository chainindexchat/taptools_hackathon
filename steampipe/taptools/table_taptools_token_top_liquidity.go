package taptools

import (
	"context"
	"fmt"
	"io"

	// "net/url"
	"encoding/json"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

func tableTaptoolsTokenTopLiquidity() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_top_liquidity",
		Description: "Get tokens ranked by their DEX liquidity. This includes both AMM and order book liquidity.",
		List: &plugin.ListConfig{
			Hydrate: listTokenTopLiquidity,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "ticker", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "unit", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "liquidity", Type: proto.ColumnType_DOUBLE, Description: ""},
			// Query parameters
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=20 Specify how many items to return per page. Maximum is 100, default is 20."},
		},
	}
}

// Define a struct to hold the response from the API
type TokenLiquidityResponseItem struct {
	Price     float64 `json:"price"`
	Liquidity float64 `json:"liquidity"`
	Ticker    string  `json:"ticker"`
	Unit      string  `json:"unit"`
	Page      int64   `json:"page"`
	PerPage   int64   `json:"perPage"`
}

func listTokenTopLiquidity(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	page := int64(1)
	perPage := int64(20)

	var reqUrl string

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

	// URL for the API endpoint with proper escaping
	reqUrl = fmt.Sprintf("https://openapi.taptools.io/api/v1/token/top/liquidity?page=%d&perPage=%d",
		page, perPage)

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
		Price     float64 `json:"price"`
		Liquidity float64 `json:"liquidity"`
		Ticker    string  `json:"ticker"`
		Unit      string  `json:"unit"`
	}
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TokenLiquidityResponseItem{
			Price:     item.Price,
			Liquidity: item.Liquidity,
			Ticker:    item.Ticker,
			Unit:      item.Unit,
			Page:      page,
			PerPage:   perPage,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			return nil, nil
		}
	}

	return nil, nil
}
