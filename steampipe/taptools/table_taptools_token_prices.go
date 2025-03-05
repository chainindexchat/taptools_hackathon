package taptools

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
)

// Define the structure for the API request and response
type TokenPriceRequest struct {
	Tokens []string `json:"tokens"`
}

type TokenPriceResponse map[string]float64

func listTokenPrices(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Since we can't directly query with parameters like in other endpoints, we'll assume the tokens are passed via some configuration or direct input which isn't shown in this example.
	// For simplicity, here we'll use a hardcoded list. In real use, you might want to handle token list input differently.

	tokens := []string{
		"dda5fdb1002f7389b33e036b6afee82a8189becb6cba852e8b79b4fb0014df1047454e53", // Example token unit
	}

	// Check if the batch size exceeds the limit
	if len(tokens) > 100 {
		return nil, fmt.Errorf("maximum batch size is 100 tokens, provided: %d", len(tokens))
	}

	// Prepare the request body
	reqBody := TokenPriceRequest{Tokens: tokens}
	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("error marshalling request body: %v", err)
	}

	// URL for the API endpoint
	reqUrl := "https://openapi.taptools.io/api/v1/token/prices"

	// Create HTTP client
	client := &http.Client{}
	req, err := http.NewRequest("POST", reqUrl, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("error creating request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
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
	var apiResponse TokenPriceResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe
	for token, price := range apiResponse {
		d.StreamListItem(ctx, map[string]interface{}{
			"token": token,
			"price": price,
		})
	}

	return nil, nil
}

func tableTaptoolsTokenPrices() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_prices",
		Description: "Get an object with token units (policy + hex name) as keys and price as values for a list of policies and hex names.",
		List: &plugin.ListConfig{
			Hydrate: listTokenPrices,
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "token", Type: proto.ColumnType_STRING, Description: "The token unit (policy + hex name)"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "The current price of the token aggregated across supported DEXs"},
		},
	}
}
