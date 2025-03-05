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
type HolderDistributionResponse struct {
	One             int64 `json:"1"`
	TwoToFour       int64 `json:"2-4"`
	FiveToNine      int64 `json:"5-9"`
	TenToTwentyFour int64 `json:"10-24"`
	TwentyFivePlus  int64 `json:"25+"`

	Policy string `json:"policy,omitempty"`
}

func listHolderDistribution(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

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
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/holders/distribution?policy=%s", policy)

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
	var apiResponse HolderDistributionResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the policy metadata
	d.StreamListItem(ctx, HolderDistributionResponse{
		One:             apiResponse.One,
		TwoToFour:       apiResponse.TwoToFour,
		FiveToNine:      apiResponse.FiveToNine,
		TenToTwentyFour: apiResponse.TenToTwentyFour,
		TwentyFivePlus:  apiResponse.TwentyFivePlus,
		Policy:          policy,
	})

	return nil, nil
}

func tableTaptoolsHolderDistribution() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_holder_distribution",
		Description: "Get the distribution of NFTs within a collection by bucketing into number of NFTs held groups.",
		List: &plugin.ListConfig{
			Hydrate: listHolderDistribution,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "one", Type: proto.ColumnType_INT, Description: "Number of holders with exactly 1 NFT"},
			{Name: "two_to_four", Type: proto.ColumnType_INT, Description: "Number of holders with 2 to 4 NFTs"},
			{Name: "five_to_nine", Type: proto.ColumnType_INT, Description: "Number of holders with 5 to 9 NFTs"},
			{Name: "ten_to_twenty_four", Type: proto.ColumnType_INT, Description: "Number of holders with 10 to 24 NFTs"},
			{Name: "twenty_five_plus", Type: proto.ColumnType_INT, Description: "Number of holders with 25 or more NFTs"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection."},
		},
	}
}
