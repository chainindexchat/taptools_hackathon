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
type CollectionInfoResponse struct {
	Description string `json:"description"`
	Discord     string `json:"discord"`
	Logo        string `json:"logo"`
	Name        string `json:"name"`
	Supply      int64  `json:"supply"`
	Twitter     string `json:"twitter"`
	Website     string `json:"website"`

	Policy string `json:"policy,omitempty"`
}

func listCollectionInfo(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

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
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/info?policy=%s", policy)

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
	var apiResponse CollectionInfoResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the policy metadata
	d.StreamListItem(ctx, CollectionInfoResponse{
		Description: apiResponse.Description,
		Discord:     apiResponse.Discord,
		Logo:        apiResponse.Logo,
		Name:        apiResponse.Name,
		Supply:      apiResponse.Supply,
		Twitter:     apiResponse.Twitter,
		Website:     apiResponse.Website,
		Policy:      policy,
	})

	return nil, nil
}

func tableTaptoolsCollectionInfo() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_collection_info",
		Description: "Get basic information about a collection like name, socials, and logo.",
		List: &plugin.ListConfig{
			Hydrate: listCollectionInfo,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "description", Type: proto.ColumnType_STRING, Description: "Description of the collection"},
			{Name: "discord", Type: proto.ColumnType_STRING, Description: "Discord server link for the collection"},
			{Name: "logo", Type: proto.ColumnType_STRING, Description: "URL of the collection's logo"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the collection"},
			{Name: "supply", Type: proto.ColumnType_INT, Description: "Total supply of NFTs in the collection"},
			{Name: "twitter", Type: proto.ColumnType_STRING, Description: "Twitter handle for the collection"},
			{Name: "website", Type: proto.ColumnType_STRING, Description: "Official website of the collection"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection."},
		},
	}
}
