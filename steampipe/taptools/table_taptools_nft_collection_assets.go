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
type CollectionAssetResponse struct {
	Image string  `json:"image"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
	Rank  int64   `json:"rank"`

	Policy  string `json:"policy,omitempty"`
	SortBy  string `json:"sortBy,omitempty"`
	OrderBy string `json:"orderBy,omitempty"` // Renamed from Order
	Search  string `json:"search,omitempty"`
	OnSale  string `json:"onSale,omitempty"`
	Page    int64  `json:"page,omitempty"`
	PerPage int64  `json:"perPage,omitempty"`
}

func listCollectionAssets(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy, sortBy, orderBy, search, onSale string // Renamed order to orderBy
	var page, perPage int64 = 1, 100                   // Default values

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_by"]; quals != nil && len(quals.Quals) > 0 {
		sortBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["order_by"]; quals != nil && len(quals.Quals) > 0 { // Renamed from "order"
		orderBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["search"]; quals != nil && len(quals.Quals) > 0 {
		search = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["on_sale"]; quals != nil && len(quals.Quals) > 0 {
		onSale = quals.Quals[0].Value.GetStringValue()
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

	// Check if policy is provided
	if policy == "" {
		return nil, fmt.Errorf("policy must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/assets?policy=%s", policy)
	if sortBy != "" {
		reqUrl += "&sortBy=" + sortBy
	}
	if orderBy != "" {
		reqUrl += "&order=" + orderBy // API expects "order" parameter
	}
	if search != "" {
		reqUrl += "&search=" + search
	}
	if onSale != "" {
		reqUrl += "&onSale=" + onSale
	}
	if page != 1 {
		reqUrl += "&page=" + strconv.FormatInt(page, 10)
	}
	if perPage != 100 {
		reqUrl += "&perPage=" + strconv.FormatInt(perPage, 10)
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
	var apiResponse []CollectionAssetResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, CollectionAssetResponse{
			Image:   item.Image,
			Name:    item.Name,
			Price:   item.Price,
			Rank:    item.Rank,
			Policy:  policy,
			SortBy:  sortBy,
			OrderBy: orderBy, // Renamed from Order
			Search:  search,
			OnSale:  onSale,
			Page:    page,
			PerPage: perPage,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsCollectionAssets() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_collection_assets",
		Description: "Get all NFTs from a collection with the ability to sort by price/rank and filter to specific traits.",
		List: &plugin.ListConfig{
			Hydrate: listCollectionAssets,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_by", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "order_by", Require: plugin.Optional, Operators: []string{"="}}, // Renamed from "order"
				{Name: "search", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "on_sale", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "image", Type: proto.ColumnType_STRING, Description: "URL of the NFT image"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the NFT"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current price of the NFT"},
			{Name: "rank", Type: proto.ColumnType_INT, Description: "Rank of the NFT within the collection"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=40fa2aa67258b4ce7b5782f74831d46a84c59a0ff0c28262fab21728 The policy ID for the collection."},
			{Name: "sort_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortBy"), Description: "Example: sortBy=price What should the results be sorted by. Options are price and rank. Default is price."},
			{Name: "order_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("OrderBy"), Description: "Example: order_by=asc Which direction should the results be sorted. Options are asc, desc. Default is asc"}, // Renamed from "order"
			{Name: "search", Type: proto.ColumnType_STRING, Transform: transform.FromField("Search"), Description: "Example: search=ClayNation3725 Search for a certain NFT's name, default is null."},
			{Name: "on_sale", Type: proto.ColumnType_STRING, Transform: transform.FromField("OnSale"), Description: "Example: onSale=1 Return only nfts that are on sale Options are 0, 1. Default is 0."},
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100."},
		},
	}
}
