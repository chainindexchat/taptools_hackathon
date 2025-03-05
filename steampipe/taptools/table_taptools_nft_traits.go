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
type NFTTrait struct {
	Category string  `json:"category"`
	Name     string  `json:"name"`
	Price    float64 `json:"price"`
	Rarity   float64 `json:"rarity"`
}

type NFTTraitsResponse struct {
	Rank   int64      `json:"rank"`
	Traits []NFTTrait `json:"traits"`
}

func listNFTTraits(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
	// Retrieve the API key from the environment
	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Extract query parameters from the query context
	var policy, name, prices string

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["name"]; quals != nil && len(quals.Quals) > 0 {
		name = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["prices"]; quals != nil && len(quals.Quals) > 0 {
		prices = quals.Quals[0].Value.GetStringValue()
	}

	// Validate required parameters
	if policy == "" || name == "" {
		return nil, fmt.Errorf("both policy and name must be provided")
	}

	// Construct the API request URL
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/asset/traits?policy=%s&name=%s", policy, name)
	if prices != "" {
		reqUrl += "&prices=" + prices
	}

	// Create and configure the HTTP request
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

	// Handle non-200 responses
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(res.Body)
		return nil, fmt.Errorf("API returned non-200 status: %d, body: %s", res.StatusCode, string(body))
	}

	// Read and decode the response
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("error reading response body: %v", err)
	}

	var apiResponse NFTTraitsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream each trait as a row to Steampipe
	for _, trait := range apiResponse.Traits {
		d.StreamListItem(ctx, map[string]interface{}{
			"rank":           apiResponse.Rank,
			"policy":         policy,
			"name":           name,
			"prices":         prices,
			"trait_category": trait.Category,
			"trait_name":     trait.Name,
			"trait_price":    trait.Price,
			"trait_rarity":   trait.Rarity,
		})
	}

	return nil, nil
}

func tableTaptoolsNFTTraits() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_traits",
		Description: "Get a specific NFT's traits and trait prices.",
		List: &plugin.ListConfig{
			Hydrate: listNFTTraits,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "name", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "prices", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "rank", Type: proto.ColumnType_INT, Transform: transform.FromField("rank"), Description: "Rank of the NFT"},
			{Name: "trait_category", Type: proto.ColumnType_STRING, Transform: transform.FromField("trait_category"), Description: "Category of the trait"},
			{Name: "trait_name", Type: proto.ColumnType_STRING, Transform: transform.FromField("trait_name"), Description: "Name of the trait"},
			{Name: "trait_price", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("trait_price"), Description: "Price of the trait"},
			{Name: "trait_rarity", Type: proto.ColumnType_DOUBLE, Transform: transform.FromField("trait_rarity"), Description: "Rarity of the trait"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("policy"), Description: "The policy ID for the collection. Example: 40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728"},
			{Name: "name", Type: proto.ColumnType_STRING, Transform: transform.FromField("name"), Description: "The name of a specific NFT to get stats for. Example: ClayNation3725"},
			{Name: "prices", Type: proto.ColumnType_STRING, Transform: transform.FromField("prices"), Description: "Whether to include trait prices (0 or 1). Default is 1. Example: 0"},
		},
	}
}
