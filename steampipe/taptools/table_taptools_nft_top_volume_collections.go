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
type TopVolumeCollectionsResponse struct {
	Listings int64   `json:"listings"`
	Logo     string  `json:"logo"`
	Name     string  `json:"name"`
	Policy   string  `json:"policy"`
	Price    float64 `json:"price"`
	Sales    int64   `json:"sales"`
	Supply   int64   `json:"supply"`
	Volume   float64 `json:"volume"`

	Timeframe string `json:"timeframe,omitempty"`
	Page      int64  `json:"page,omitempty"`
	PerPage   int64  `json:"perPage,omitempty"`
}

func listTopVolumeCollections(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var timeframe string
	var page, perPage int64 = 1, 10 // Default values

	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
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

	// URL for the API endpoint with proper escaping
	reqUrl := "https://openapi.taptools.io/api/v1/nft/top/volume"
	if timeframe != "" {
		reqUrl += "?timeframe=" + timeframe
	}
	if page != 1 {
		if timeframe != "" {
			reqUrl += "&page=" + strconv.FormatInt(page, 10)
		} else {
			reqUrl += "?page=" + strconv.FormatInt(page, 10)
		}
	}
	if perPage != 10 {
		if timeframe != "" || page != 1 {
			reqUrl += "&perPage=" + strconv.FormatInt(perPage, 10)
		} else {
			reqUrl += "?perPage=" + strconv.FormatInt(perPage, 10)
		}
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
	var apiResponse []TopVolumeCollectionsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TopVolumeCollectionsResponse{
			Listings:  item.Listings,
			Logo:      item.Logo,
			Name:      item.Name,
			Policy:    item.Policy,
			Price:     item.Price,
			Sales:     item.Sales,
			Supply:    item.Supply,
			Volume:    item.Volume,
			Timeframe: timeframe,
			Page:      page,
			PerPage:   perPage,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsTopVolumeCollections() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_top_volume_collections",
		Description: "Get top NFT collections by trading volume over a given timeframe.",
		List: &plugin.ListConfig{
			Hydrate: listTopVolumeCollections,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "listings", Type: proto.ColumnType_INT, Description: "Number of current listings for the collection"},
			{Name: "logo", Type: proto.ColumnType_STRING, Description: "URL of the collection's logo"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the collection"},
			{Name: "policy", Type: proto.ColumnType_STRING, Description: "Policy ID of the collection"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current price of the collection"},
			{Name: "sales", Type: proto.ColumnType_INT, Description: "Number of sales"},
			{Name: "supply", Type: proto.ColumnType_INT, Description: "Total supply of NFTs in the collection"},
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Description: "Trading volume of the collection"},

			// Query parameters
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=24h What timeframe to include in volume aggregation. Options are 1h, 4h, 24h, 7d, 30d, all. Defaults to 24h."},
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10."},
		},
	}
}
