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
type NFTTopRankingsResponse struct {
	Listings     int64   `json:"listings"`
	Logo         string  `json:"logo"`
	MarketCap    float64 `json:"marketCap"`
	Name         string  `json:"name"`
	Policy       string  `json:"policy"`
	Price        float64 `json:"price"`
	Price24hChg  float64 `json:"price24hChg"`
	Price30dChg  float64 `json:"price30dChg"`
	Price7dChg   float64 `json:"price7dChg"`
	Rank         int64   `json:"rank"`
	Supply       int64   `json:"supply"`
	Volume24h    float64 `json:"volume24h"`
	Volume24hChg float64 `json:"volume24hChg"`
	Volume30d    float64 `json:"volume30d"`
	Volume30dChg float64 `json:"volume30dChg"`
	Volume7d     float64 `json:"volume7d"`
	Volume7dChg  float64 `json:"volume7dChg"`

	Ranking string `json:"ranking,omitempty"`
	Items   int64  `json:"items,omitempty"`
}

func listNFTTopRankings(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var ranking string
	var items int64 = 25 // Default value

	if quals := d.Quals["ranking"]; quals != nil && len(quals.Quals) > 0 {
		ranking = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["items"]; quals != nil && len(quals.Quals) > 0 {
		items = quals.Quals[0].Value.GetInt64Value()
		if items > 100 {
			items = 100 // Max items is 100
		}
	}

	// Check if ranking is provided
	if ranking == "" {
		return nil, fmt.Errorf("ranking must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/nft/top/timeframe?ranking=%s", ranking)
	if items != 25 {
		reqUrl += "&items=" + strconv.FormatInt(items, 10)
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
		case http.StatusNotAcceptable:
			return nil, fmt.Errorf("not acceptable")
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
	var apiResponse []NFTTopRankingsResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, NFTTopRankingsResponse{
			Listings:     item.Listings,
			Logo:         item.Logo,
			MarketCap:    item.MarketCap,
			Name:         item.Name,
			Policy:       item.Policy,
			Price:        item.Price,
			Price24hChg:  item.Price24hChg,
			Price30dChg:  item.Price30dChg,
			Price7dChg:   item.Price7dChg,
			Rank:         item.Rank,
			Supply:       item.Supply,
			Volume24h:    item.Volume24h,
			Volume24hChg: item.Volume24hChg,
			Volume30d:    item.Volume30d,
			Volume30dChg: item.Volume30dChg,
			Volume7d:     item.Volume7d,
			Volume7dChg:  item.Volume7dChg,
			Ranking:      ranking,
			Items:        items,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsNFTTopRankings() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_top_rankings",
		Description: "Get top NFT rankings based on total market cap, 24 hour volume or 24 hour top price gainers/losers.",
		List: &plugin.ListConfig{
			Hydrate: listNFTTopRankings,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "ranking", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "items", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "listings", Type: proto.ColumnType_INT, Description: "Number of listings for the collection"},
			{Name: "logo", Type: proto.ColumnType_STRING, Description: "URL of the collection's logo"},
			{Name: "market_cap", Type: proto.ColumnType_DOUBLE, Description: "Market capitalization of the collection"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the collection"},
			{Name: "policy", Type: proto.ColumnType_STRING, Description: "Policy ID of the collection"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Current price"},
			{Name: "price_24h_chg", Type: proto.ColumnType_DOUBLE, Description: "Price change in the last 24 hours"},
			{Name: "price_30d_chg", Type: proto.ColumnType_DOUBLE, Description: "Price change in the last 30 days"},
			{Name: "price_7d_chg", Type: proto.ColumnType_DOUBLE, Description: "Price change in the last 7 days"},
			{Name: "rank", Type: proto.ColumnType_INT, Description: "Ranking based on specified criteria"},
			{Name: "supply", Type: proto.ColumnType_INT, Description: "Total supply of NFTs in the collection"},
			{Name: "volume_24h", Type: proto.ColumnType_DOUBLE, Description: "Volume traded in the last 24 hours"},
			{Name: "volume_24h_chg", Type: proto.ColumnType_DOUBLE, Description: "Volume change in the last 24 hours"},
			{Name: "volume_30d", Type: proto.ColumnType_DOUBLE, Description: "Volume traded in the last 30 days"},
			{Name: "volume_30d_chg", Type: proto.ColumnType_DOUBLE, Description: "Volume change in the last 30 days"},
			{Name: "volume_7d", Type: proto.ColumnType_DOUBLE, Description: "Volume traded in the last 7 days"},
			{Name: "volume_7d_chg", Type: proto.ColumnType_DOUBLE, Description: "Volume change in the last 7 days"},

			// Query parameters
			{Name: "ranking", Type: proto.ColumnType_STRING, Transform: transform.FromField("Ranking"), Description: "Example: ranking=marketCap Criteria to rank NFT Collections based on. Options are marketCap, volume, gainers, losers."},
			{Name: "items", Type: proto.ColumnType_INT, Transform: transform.FromField("Items"), Description: "Example: items=50 Specify how many items to return. Maximum is 100, default is 25."},
		},
	}
}
