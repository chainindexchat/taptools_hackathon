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
type NFTMarketplaceStatsResponse struct {
	AvgSale   float64 `json:"avgSale"`
	Fees      float64 `json:"fees"`
	Liquidity float64 `json:"liquidity"`
	Listings  int64   `json:"listings"`
	Name      string  `json:"name"`
	Royalties float64 `json:"royalties"`
	Sales     int64   `json:"sales"`
	Users     int64   `json:"users"`
	Volume    float64 `json:"volume"`

	Timeframe   string `json:"timeframe,omitempty"`
	Marketplace string `json:"marketplace,omitempty"`
	LastDay     int64  `json:"lastDay,omitempty"`
}

func listNFTMarketplaceStats(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var timeframe, marketplace string
	var lastDay int64

	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["marketplace"]; quals != nil && len(quals.Quals) > 0 {
		marketplace = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["last_day"]; quals != nil && len(quals.Quals) > 0 {
		lastDay = quals.Quals[0].Value.GetInt64Value()
	}

	// URL for the API endpoint with proper escaping
	reqUrl := "https://openapi.taptools.io/api/v1/nft/marketplace/stats"
	if timeframe != "" {
		reqUrl += "?timeframe=" + timeframe
	}
	if marketplace != "" {
		if timeframe != "" {
			reqUrl += "&marketplace=" + marketplace
		} else {
			reqUrl += "?marketplace=" + marketplace
		}
	}
	if lastDay != 0 {
		if timeframe != "" || marketplace != "" {
			reqUrl += "&lastDay=" + fmt.Sprintf("%d", lastDay)
		} else {
			reqUrl += "?lastDay=" + fmt.Sprintf("%d", lastDay)
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
	var item NFTMarketplaceStatsResponse
	if err := json.Unmarshal(body, &item); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	// for _, item := range apiResponse {
	d.StreamListItem(ctx, NFTMarketplaceStatsResponse{
		AvgSale:     item.AvgSale,
		Fees:        item.Fees,
		Liquidity:   item.Liquidity,
		Listings:    item.Listings,
		Name:        item.Name,
		Royalties:   item.Royalties,
		Sales:       item.Sales,
		Users:       item.Users,
		Volume:      item.Volume,
		Timeframe:   timeframe,
		Marketplace: marketplace,
		LastDay:     lastDay,
	})

	// Check if we need to stop due to LIMIT being reached
	// if d.RowsRemaining(ctx) == 0 {
	// 	break
	// }
	// }

	return nil, nil
}

func tableTaptoolsNFTMarketplaceStats() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_marketplace_stats",
		Description: "Get high-level NFT marketplace stats.",
		List: &plugin.ListConfig{
			Hydrate: listNFTMarketplaceStats,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "marketplace", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "last_day", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "avg_sale", Type: proto.ColumnType_DOUBLE, Description: "Average sale price"},
			{Name: "fees", Type: proto.ColumnType_DOUBLE, Description: "Total fees collected"},
			{Name: "liquidity", Type: proto.ColumnType_DOUBLE, Description: "Liquidity in the marketplace"},
			{Name: "listings", Type: proto.ColumnType_INT, Description: "Number of current listings"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the marketplace"},
			{Name: "royalties", Type: proto.ColumnType_DOUBLE, Description: "Total royalties paid"},
			{Name: "sales", Type: proto.ColumnType_INT, Description: "Number of sales"},
			{Name: "users", Type: proto.ColumnType_INT, Description: "Number of unique users"},
			{Name: "volume", Type: proto.ColumnType_DOUBLE, Description: "Total trading volume"},

			// Query parameters
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=30d The time interval. Options are 24h, 7d, 30d, 90d, 180d, all. Defaults to 7d."},
			{Name: "marketplace", Type: proto.ColumnType_STRING, Transform: transform.FromField("Marketplace"), Description: "Example: marketplace=jpg.store Filters data to a certain marketplace by name."},
			{Name: "last_day", Type: proto.ColumnType_INT, Transform: transform.FromField("LastDay"), Description: "Example: lastDay=0 Filters to only count data that occurred between yesterday 00:00UTC and today 00:00UTC (0,1)."},
		},
	}
}
