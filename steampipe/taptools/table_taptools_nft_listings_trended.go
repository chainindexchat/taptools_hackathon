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
type NFTListingsTrendedResponse struct {
	Listings int64   `json:"listings"`
	Price    float64 `json:"price"`
	Time     int64   `json:"time"`

	Policy       string `json:"policy,omitempty"`
	Interval     string `json:"interval,omitempty"`
	NumIntervals int64  `json:"numIntervals,omitempty"`
}

func listNFTListingsTrended(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy, interval string
	var numIntervals int64

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["interval"]; quals != nil && len(quals.Quals) > 0 {
		interval = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["num_intervals"]; quals != nil && len(quals.Quals) > 0 {
		numIntervals = quals.Quals[0].Value.GetInt64Value()
	}

	// Check if policy and interval are provided
	if policy == "" || interval == "" {
		return nil, fmt.Errorf("both policy and interval must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/collection/listings/trended?policy=%s&interval=%s", policy, interval)
	if numIntervals != 0 {
		reqUrl += "&numIntervals=" + strconv.FormatInt(numIntervals, 10)
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
	var apiResponse []NFTListingsTrendedResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, NFTListingsTrendedResponse{
			Listings:     item.Listings,
			Price:        item.Price,
			Time:         item.Time,
			Policy:       policy,
			Interval:     interval,
			NumIntervals: numIntervals,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsNFTListingsTrended() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_listings_trended",
		Description: "Get trended number of listings and floor price for a particular NFT collection.",
		List: &plugin.ListConfig{
			Hydrate: listNFTListingsTrended,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "interval", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "num_intervals", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "listings", Type: proto.ColumnType_INT, Description: "Number of listings at this time point"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Floor price at this time point"},
			{Name: "time", Type: proto.ColumnType_INT, Description: "Unix timestamp for the data point"},

			// Query parameters
			{Name: "policy", Type: proto.ColumnType_STRING, Transform: transform.FromField("Policy"), Description: "Example: policy=1fcf4baf8e7465504e115dcea4db6da1f7bed335f2a672e44ec3f94e The policy ID for the collection."},
			{Name: "interval", Type: proto.ColumnType_STRING, Transform: transform.FromField("Interval"), Description: "Example: interval=1d The time interval. Options are 3m, 5m, 15m, 30m, 1h, 2h, 4h, 12h, 1d, 3d, 1w, 1M."},
			{Name: "num_intervals", Type: proto.ColumnType_INT, Transform: transform.FromField("NumIntervals"), Description: "Example: numIntervals=180 The number of intervals to return, e.g. if you want 180 days of data in 1d intervals, then pass 180 here. Leave blank for full history."},
		},
	}
}
