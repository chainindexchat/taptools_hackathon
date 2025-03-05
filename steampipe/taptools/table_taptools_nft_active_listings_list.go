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
type ActiveListingsIndividualResponse struct {
	Image  string  `json:"image"`
	Market string  `json:"market"`
	Name   string  `json:"name"`
	Price  float64 `json:"price"`
	Time   int64   `json:"time"`

	Policy  string `json:"policy,omitempty"`
	SortBy  string `json:"sortBy,omitempty"`
	OrderBy string `json:"orderBy,omitempty"` // Renamed from Order
	Page    int64  `json:"page,omitempty"`
	PerPage int64  `json:"perPage,omitempty"`
}

func listActiveListingsIndividual(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy, sortBy, orderBy string // Renamed order to orderBy
	var page, perPage int64 = 1, 100   // Default values

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_by"]; quals != nil && len(quals.Quals) > 0 {
		sortBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["order_by"]; quals != nil && len(quals.Quals) > 0 { // Renamed from "order"
		orderBy = quals.Quals[0].Value.GetStringValue()
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
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/listings/individual?policy=%s", policy)
	if sortBy != "" {
		reqUrl += "&sortBy=" + sortBy
	}
	if orderBy != "" {
		reqUrl += "&order=" + orderBy // API still uses "order" parameter
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
	var apiResponse []ActiveListingsIndividualResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, ActiveListingsIndividualResponse{
			Image:   item.Image,
			Market:  item.Market,
			Name:    item.Name,
			Price:   item.Price,
			Time:    item.Time,
			Policy:  policy,
			SortBy:  sortBy,
			OrderBy: orderBy, // Renamed from Order
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

func tableTaptoolsActiveListingsIndividual() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_active_listings_individual",
		Description: "Get a list of active listings with supporting information.",
		List: &plugin.ListConfig{
			Hydrate: listActiveListingsIndividual,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_by", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "order_by", Require: plugin.Optional, Operators: []string{"="}}, // Renamed from "order"
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "image", Type: proto.ColumnType_STRING, Description: "URL of the NFT's image"},
			{Name: "market", Type: proto.ColumnType_STRING, Description: "Marketplace where the NFT is listed"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the NFT"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current listing price of the NFT"},
			{Name: "time", Type: proto.ColumnType_INT, Description: "Unix timestamp when the NFT was listed"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection."},
			{Name: "sort_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortBy"), Description: "Example: sortBy=price What should the results be sorted by. Options are price, time. Default is price."},
			{Name: "order_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("OrderBy"), Description: "Example: order_by=asc Which direction should the results be sorted. Options are asc, desc. Default is asc"}, // Renamed from "order"
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100."},
		},
	}
}
