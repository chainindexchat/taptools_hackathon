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
type QuotePriceResponse struct {
	Price float64 `json:"price"`
	Quote string  `json:"quote,omitempty"` // not in the response but used for metadata
}

func listQuotePrice(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var quote string = "USD" // Default value

	if quals := d.Quals["quote"]; quals != nil && len(quals.Quals) > 0 {
		quote = quals.Quals[0].Value.GetStringValue()
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/quote?quote=%s", quote)

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
	var apiResponse QuotePriceResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the quote metadata
	d.StreamListItem(ctx, QuotePriceResponse{
		Price: apiResponse.Price,
		Quote: quote,
	})

	return nil, nil
}

func tableTaptoolsQuotePrice() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_quote_price",
		Description: "Get current quote price (e.g., current ADA/USD price).",
		List: &plugin.ListConfig{
			Hydrate: listQuotePrice,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "quote", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current price of the quote currency"},

			// Query parameters
			{Name: "quote", Type: proto.ColumnType_STRING, Transform: transform.FromField("Quote"), Description: "Example: quote=USD Quote currency to use (USD, EUR, ETH, BTC). Default is USD."},
		},
	}
}
