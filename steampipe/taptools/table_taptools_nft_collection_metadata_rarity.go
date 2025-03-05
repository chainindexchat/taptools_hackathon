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

func listCollectionMetadataRarity(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy string
	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}

	// Check if policy is provided
	if policy == "" {
		return nil, fmt.Errorf("policy must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/traits/rarity?policy=%s", policy)

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

	// Decode JSON response into a map matching the API structure
	var apiResponse map[string]map[string]float64
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for category, items := range apiResponse {
		for item, probability := range items {
			d.StreamListItem(ctx, map[string]interface{}{
				"policy":      policy,
				"category":    category,
				"attribute":   item, // Renamed "item" to "attribute" for clarity
				"probability": probability,
			})
		}
	}

	return nil, nil
}

func tableTaptoolsCollectionMetadataRarity() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_collection_metadata_rarity",
		Description: "Get every metadata attribute and how likely it is to occur within the NFT collection.",
		List: &plugin.ListConfig{
			Hydrate: listCollectionMetadataRarity,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Required, Operators: []string{"="}}, // Changed to Required per API doc
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "category", Type: proto.ColumnType_STRING, Transform: transform.FromField("category"), Description: "The category of the metadata attribute (e.g., Accessories, Background)"},
			{Name: "attribute", Type: proto.ColumnType_STRING, Transform: transform.FromField("attribute"), Description: "The specific attribute within the category (e.g., Bowtie, Cyan)"},
			{Name: "probability", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("probability"), Description: "The probability of occurrence for this attribute (e.g., 0.0709)"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("policy"), Description: "The policy ID for the collection. Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e"},
		},
	}
}
