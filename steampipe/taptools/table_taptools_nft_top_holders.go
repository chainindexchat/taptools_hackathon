package taptools

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

// Define the structure for the API response
type TopHoldersResponse struct {
	Address string `json:"address"`
	Amount  int64  `json:"amount"`

	Policy           string `json:"policy,omitempty"`
	Page             int64  `json:"page,omitempty"`
	PerPage          int64  `json:"perPage,omitempty"`
	ExcludeExchanges int64  `json:"excludeExchanges,omitempty"`
}

func listTopHolders(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy string
	var page, perPage, excludeExchanges int64 = 1, 10, 0 // Default values

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["page"]; quals != nil && len(quals.Quals) > 0 {
		page = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["per_page"]; quals != nil && len(quals.Quals) > 0 {
		perPage = quals.Quals[0].Value.GetInt64Value()
		if perPage > 100 {
			perPage = 100 // Max perPage is 100
		}
	}
	if quals := d.Quals["exclude_exchanges"]; quals != nil && len(quals.Quals) > 0 {
		excludeExchanges = quals.Quals[0].Value.GetInt64Value()
	}

	// Check if policy is provided
	if policy == "" {
		return nil, fmt.Errorf("policy must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/holders/top?policy=%s", policy)
	if page != 1 {
		reqUrl += "&page=" + strconv.FormatInt(page, 10)
	}
	if perPage != 10 {
		reqUrl += "&perPage=" + strconv.FormatInt(perPage, 10)
	}
	if excludeExchanges != 0 {
		reqUrl += "&excludeExchanges=" + strconv.FormatInt(excludeExchanges, 10)
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
	var apiResponse []TopHoldersResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TopHoldersResponse{
			Address:          item.Address,
			Amount:           item.Amount,
			Policy:           policy,
			Page:             page,
			PerPage:          perPage,
			ExcludeExchanges: excludeExchanges,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsTokenTopHolders() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_top_holders",
		Description: "Get the top holders for a particular NFT collection.",
		List: &plugin.ListConfig{
			Hydrate: listTopHolders,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "exclude_exchanges", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "address", Type: proto.ColumnType_STRING, Description: "Address of the holder"},
			{Name: "amount", Type: proto.ColumnType_INT, Description: "Number of NFTs held by the address"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection."},
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10."},
			{Name: "exclude_exchanges", Type: proto.ColumnType_INT, Transform: transform.FromField("ExcludeExchanges"), Description: "Example: excludeExchanges=1 Whether or not to exclude marketplace addresses (0, 1)"},
		},
	}
}
