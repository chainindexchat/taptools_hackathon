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

// Define the structure for a single trait price entry
type TraitPrice struct {
	Price float64 `json:"number"`
}

// Define the structure for the API response (not used directly for streaming)
type CollectionTraitPricesResponse struct {
	Policy string                           `json:"policy,omitempty"`
	Name   string                           `json:"name,omitempty"`
	Traits map[string]map[string]TraitPrice `json:"object"`
}

func listCollectionTraitPrices(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy, name string

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["name"]; quals != nil && len(quals.Quals) > 0 {
		name = quals.Quals[0].Value.GetStringValue()
	}

	// Check if policy is provided
	if policy == "" {
		return nil, fmt.Errorf("policy must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/traits/price?policy=%s", policy)
	if name != "" {
		reqUrl += "&name=" + name
	}
	plugin.Logger(ctx).Info(reqUrl)
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
		switch res.StatusCode {
		case http.StatusBadRequest:
			return nil, fmt.Errorf("bad request")
		case http.StatusUnauthorized:
			return nil, fmt.Errorf("not authorized")
		case http.StatusNotFound:
			return nil, fmt.Errorf("not found")
		case http.StatusTooManyRequests:
			return nil, fmt.Errorf("rate limit exceeded")
		case http.StatusInternalServerError:
			return nil, fmt.Errorf("interval server error")
		default:
			body, _ := io.ReadAll(res.Body)
			return nil, fmt.Errorf("API returned non-200 status: %d, body: %s", res.StatusCode, string(body))
		}
	}

	// Read the response body
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("error reading response body: %v", err)
	}

	// Decode JSON response
	var apiResponse map[string]map[string]float64
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for category, traits := range apiResponse {
		for trait, price := range traits {
			d.StreamListItem(ctx, map[string]interface{}{
				"policy":   policy,
				"name":     name,
				"category": category,
				"trait":    trait,
				"price":    price,
			})
		}
	}

	return nil, nil
}

func tableTaptoolsCollectionTraitPrices() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_collection_trait_prices",
		Description: "Get a list of traits within a collection and each trait's floor price.",
		List: &plugin.ListConfig{
			Hydrate: listCollectionTraitPrices,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "name", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "category", Type: proto.ColumnType_STRING, Transform: transform.FromField("category"), Description: "The category of the trait"},
			{Name: "trait", Type: proto.ColumnType_STRING, Transform: transform.FromField("trait"), Description: "The specific trait within the category"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("price"), Description: "The floor price of the trait"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("policy"), Description: "Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection."},
			{Name: "name", Type: proto.ColumnType_STRING, Transform: transform.FromField("name"), Description: "Example: name=ClayNation3725 The name of a specific NFT to get trait prices for."},
		},
	}
}
