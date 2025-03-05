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
type CollectionStatsExtendedResponse struct {
	Listings       int64   `json:"listings"`
	ListingsPctChg float64 `json:"listingsPctChg"`
	Owners         int64   `json:"owners"`
	OwnersPctChg   float64 `json:"ownersPctChg"`
	Price          float64 `json:"price"`
	PricePctChg    float64 `json:"pricePctChg"`
	Sales          float64 `json:"sales"`
	SalesPctChg    float64 `json:"salesPctChg"`
	Supply         int64   `json:"supply"`
	TopOffer       float64 `json:"topOffer"`
	Volume         float64 `json:"volume"`
	VolumePctChg   float64 `json:"volumePctChg"`

	Policy    string `json:"policy,omitempty"`
	Timeframe string `json:"timeframe,omitempty"`
}

func listCollectionStatsExtended(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy, timeframe string

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
	}

	// Check if policy is provided
	if policy == "" {
		return nil, fmt.Errorf("policy must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/stats/extended?policy=%s", policy)
	if timeframe != "" {
		reqUrl += "&timeframe=" + timeframe
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
	var apiResponse CollectionStatsExtendedResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the policy and timeframe metadata
	d.StreamListItem(ctx, CollectionStatsExtendedResponse{
		Listings:       apiResponse.Listings,
		ListingsPctChg: apiResponse.ListingsPctChg,
		Owners:         apiResponse.Owners,
		OwnersPctChg:   apiResponse.OwnersPctChg,
		Price:          apiResponse.Price,
		PricePctChg:    apiResponse.PricePctChg,
		Sales:          apiResponse.Sales,
		SalesPctChg:    apiResponse.SalesPctChg,
		Supply:         apiResponse.Supply,
		TopOffer:       apiResponse.TopOffer,
		Volume:         apiResponse.Volume,
		VolumePctChg:   apiResponse.VolumePctChg,
		Policy:         policy,
		Timeframe:      timeframe,
	})

	return nil, nil
}

func tableTaptoolsCollectionStatsExtended() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_collection_stats_extended",
		Description: "Get extended information about a collection including percentage changes over time.",
		List: &plugin.ListConfig{
			Hydrate: listCollectionStatsExtended,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "listings", Type: proto.ColumnType_INT, Description: "Number of current listings for the collection"},
			{Name: "listings_pct_chg", Type: proto.ColumnType_DOUBLE, Description: "Percentage change in listings"},
			{Name: "owners", Type: proto.ColumnType_INT, Description: "Number of unique owners"},
			{Name: "owners_pct_chg", Type: proto.ColumnType_DOUBLE, Description: "Percentage change in owners"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current floor price of the collection"},
			{Name: "price_pct_chg", Type: proto.ColumnType_DOUBLE, Description: "Percentage change in price"},
			{Name: "sales", Type: proto.ColumnType_DOUBLE, Description: "Total number of sales"},
			{Name: "sales_pct_chg", Type: proto.ColumnType_DOUBLE, Description: "Percentage change in sales"},
			{Name: "supply", Type: proto.ColumnType_INT, Description: "Total supply of NFTs in the collection"},
			{Name: "top_offer", Type: proto.ColumnType_DOUBLE, Description: "Highest offer currently on the collection"},
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Description: "Lifetime trading volume of the collection"},
			{Name: "volume_pct_chg", Type: proto.ColumnType_DOUBLE, Description: "Percentage change in volume"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection."},
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=24h The time interval. Options are 24h, 7d, 30d. Defaults to 24h."},
		},
	}
}
