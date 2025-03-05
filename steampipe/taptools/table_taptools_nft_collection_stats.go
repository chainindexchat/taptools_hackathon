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
type CollectionStatsResponse struct {
	Listings int64   `json:"listings"`
	Owners   int64   `json:"owners"`
	Price    float64 `json:"price"`
	Sales    float64 `json:"sales"`
	Supply   int64   `json:"supply"`
	TopOffer float64 `json:"topOffer"`
	Volume   float64 `json:"volume"`

	Policy string `json:"policy,omitempty"`
}

func listCollectionStats(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

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
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/stats?policy=%s", policy)

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
	var apiResponse CollectionStatsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the policy metadata
	d.StreamListItem(ctx, CollectionStatsResponse{
		Listings: apiResponse.Listings,
		Owners:   apiResponse.Owners,
		Price:    apiResponse.Price,
		Sales:    apiResponse.Sales,
		Supply:   apiResponse.Supply,
		TopOffer: apiResponse.TopOffer,
		Volume:   apiResponse.Volume,
		Policy:   policy,
	})

	return nil, nil
}

func tableTaptoolsCollectionStats() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_collection_stats",
		Description: "Get basic information about a collection like floor price, volume, and supply.",
		List: &plugin.ListConfig{
			Hydrate: listCollectionStats,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "listings", Type: proto.ColumnType_INT, Description: "Number of current listings for the collection"},
			{Name: "owners", Type: proto.ColumnType_INT, Description: "Number of unique owners"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current floor price of the collection"},
			{Name: "sales", Type: proto.ColumnType_DOUBLE, Description: "Total number of sales"},
			{Name: "supply", Type: proto.ColumnType_INT, Description: "Total supply of NFTs in the collection"},
			{Name: "top_offer", Type: proto.ColumnType_DOUBLE, Description: "Highest offer currently on the collection"},
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Description: "Lifetime trading volume of the collection"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection."},
		},
	}
}
