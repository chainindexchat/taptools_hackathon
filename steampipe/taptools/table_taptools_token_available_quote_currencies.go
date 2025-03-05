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
)

// Define the structure for the API response
type AvailableQuoteCurrenciesResponse struct {
	Currency string `json:"string"`
}

func listAvailableQuoteCurrencies(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// URL for the API endpoint
	reqUrl := "https://openapi.taptools.io/api/v1/token/quote/available"

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
	var apiResponse []string
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe
	for _, currency := range apiResponse {
		d.StreamListItem(ctx, AvailableQuoteCurrenciesResponse{
			Currency: currency,
		})
	}

	return nil, nil
}

func tableTaptoolsAvailableQuoteCurrencies() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_available_quote_currencies",
		Description: "Get all currently available quote currencies.",
		List: &plugin.ListConfig{
			Hydrate: listAvailableQuoteCurrencies,
		},
		Columns: []*plugin.Column{
			{Name: "currency", Type: proto.ColumnType_STRING, Description: "Available quote currency"},
		},
	}
}
