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
type NFTHistoryResponse struct {
	BuyerStakeAddress  string  `json:"buyerStakeAddress"`
	Price              float64 `json:"price"`
	SellerStakeAddress string  `json:"sellerStakeAddress"`
	Time               int64   `json:"time"`

	Policy string `json:"policy,omitempty"`
	Name   string `json:"name,omitempty"`
}

func listNFTHistory(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

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
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/asset/sales?policy=%s", policy)
	if name != "" {
		reqUrl += "&name=" + name
	}

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
	var apiResponse []NFTHistoryResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, NFTHistoryResponse{
			BuyerStakeAddress:  item.BuyerStakeAddress,
			Price:              item.Price,
			SellerStakeAddress: item.SellerStakeAddress,
			Time:               item.Time,
			Policy:             policy,
			Name:               name,
		})
	}

	return nil, nil
}

func tableTaptoolsNFTHistory() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_history",
		Description: "Get a specific asset's sale history.",
		List: &plugin.ListConfig{
			Hydrate: listNFTHistory,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "name", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "buyer_stake_address", Type: proto.ColumnType_STRING, Description: "Buyer's stake address"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Sale price of the NFT"},
			{Name: "seller_stake_address", Type: proto.ColumnType_STRING, Description: "Seller's stake address"},
			{Name: "time", Type: proto.ColumnType_INT, Description: "Unix timestamp of the sale"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection."},
			{Name: "name", Type: proto.ColumnType_STRING, Transform: transform.FromField("Name"), Description: "Example: name=ClayNation3725 The name of a specific NFT to get stats for."},
		},
	}
}
