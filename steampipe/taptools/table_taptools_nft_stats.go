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

// Define the structure for the API response with corrected types
type NFTStatsResponse struct {
	IsListed        bool    `json:"isListed"`
	LastListedPrice float64 `json:"lastListedPrice"`
	LastListedTime  int64   `json:"lastListedTime"`
	LastSoldPrice   float64 `json:"lastSoldPrice"`
	LastSoldTime    int64   `json:"lastSoldTime"`
	Owners          float64 `json:"owners"`      // Changed to float64
	Sales           float64 `json:"sales"`       // Changed to float64
	TimesListed     float64 `json:"timesListed"` // Changed to float64
	Volume          float64 `json:"volume"`

	Policy string `json:"policy,omitempty"`
	Name   string `json:"name,omitempty"`
}

func listNFTStats(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
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

	// Check if policy and name are provided
	if policy == "" || name == "" {
		return nil, fmt.Errorf("both policy and name must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/asset/stats?policy=%s&name=%s", policy, name)

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
		body, _ := io.ReadAll(res.Body) // Read the error body for debugging
		return nil, fmt.Errorf("API returned non-200 status: %d, body: %s", res.StatusCode, string(body))
	}

	// Read the response body
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("error reading response body: %v", err)
	}

	// Decode JSON response
	var apiResponse NFTStatsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the policy and name metadata
	d.StreamListItem(ctx, NFTStatsResponse{
		IsListed:        apiResponse.IsListed,
		LastListedPrice: apiResponse.LastListedPrice,
		LastListedTime:  apiResponse.LastListedTime,
		LastSoldPrice:   apiResponse.LastSoldPrice,
		LastSoldTime:    apiResponse.LastSoldTime,
		Owners:          apiResponse.Owners,
		Sales:           apiResponse.Sales,
		TimesListed:     apiResponse.TimesListed,
		Volume:          apiResponse.Volume,
		Policy:          policy,
		Name:            name,
	})

	return nil, nil
}

func tableTaptoolsNFTStats() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_stats",
		Description: "Get high-level stats on a certain NFT asset.",
		List: &plugin.ListConfig{
			Hydrate: listNFTStats,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "name", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "is_listed", Type: proto.ColumnType_BOOL, Transform: transform.FromField("IsListed"), Description: "Whether the NFT is currently listed for sale"},
			{Name: "last_listed_price", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("LastListedPrice"), Description: "The price at which the NFT was last listed"},
			{Name: "last_listed_time", Type: proto.ColumnType_INT, Transform: transform.FromField("LastListedTime"), Description: "Unix timestamp when the NFT was last listed"},
			{Name: "last_sold_price", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("LastSoldPrice"), Description: "The price at which the NFT was last sold"},
			{Name: "last_sold_time", Type: proto.ColumnType_INT, Transform: transform.FromField("LastSoldTime"), Description: "Unix timestamp when the NFT was last sold"},
			{Name: "owners", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("Owners"), Description: "Number of unique owners of this NFT"},                 // Changed to DOUBLE
			{Name: "sales", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("Sales"), Description: "Total number of sales for this NFT"},                    // Changed to DOUBLE
			{Name: "times_listed", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("TimesListed"), Description: "Number of times this NFT has been listed"}, // Changed to DOUBLE
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("Volume"), Description: "Total trading volume of this NFT"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection."},
			{Name: "name", Type: proto.ColumnType_STRING, Transform: transform.FromField("Name"), Description: "Example: name=ClayNation3725 The name of a specific NFT to get stats for."},
		},
	}
}
