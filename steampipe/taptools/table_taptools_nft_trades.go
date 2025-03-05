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
type NFTTradesResponse struct {
	BuyerAddress   string  `json:"buyerAddress"`
	CollectionName string  `json:"collectionName"`
	Hash           string  `json:"hash"`
	Image          string  `json:"image"`
	Market         string  `json:"market"`
	Name           string  `json:"name"`
	Policy         string  `json:"policy"`
	Price          float64 `json:"price"`
	SellerAddress  string  `json:"sellerAddress"`
	Time           int64   `json:"time"`

	Timeframe     string `json:"timeframe,omitempty"`
	SortBy        string `json:"sortBy,omitempty"`
	OrderBy       string `json:"orderBy,omitempty"` // Renamed from Order
	MinAmount     int64  `json:"minAmount,omitempty"`
	FromTimestamp int64  `json:"fromTimestamp,omitempty"` // Renamed from From
	Page          int64  `json:"page,omitempty"`
	PerPage       int64  `json:"perPage,omitempty"`
}

func listNFTTrades(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {
	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var policy, timeframe, sortBy, orderBy string     // Renamed order to orderBy
	var minAmount, fromTimestamp, page, perPage int64 // Renamed from to fromTimestamp

	if quals := d.Quals["policy"]; quals != nil && len(quals.Quals) > 0 {
		policy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_by"]; quals != nil && len(quals.Quals) > 0 {
		sortBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["order_by"]; quals != nil && len(quals.Quals) > 0 { // Renamed from "order"
		orderBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["min_amount"]; quals != nil && len(quals.Quals) > 0 {
		minAmount = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["from_timestamp"]; quals != nil && len(quals.Quals) > 0 { // Renamed from "from"
		fromTimestamp = quals.Quals[0].Value.GetInt64Value()
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
	reqUrl := "https://openapi.taptools.io/api/v1/nft/collection/trades"
	if policy != "" {
		reqUrl += "?policy=" + policy
	} else {
		reqUrl += "?"
	}
	if timeframe != "" {
		reqUrl += "&timeframe=" + timeframe
	}
	if sortBy != "" {
		reqUrl += "&sortBy=" + sortBy
	}
	if orderBy != "" {
		reqUrl += "&order=" + orderBy // API expects "order" parameter
	}
	if minAmount != 0 {
		reqUrl += "&minAmount=" + strconv.FormatInt(minAmount, 10)
	}
	if fromTimestamp != 0 {
		reqUrl += "&from=" + strconv.FormatInt(fromTimestamp, 10) // API expects "from" parameter
	}
	if page != 0 {
		reqUrl += "&page=" + strconv.FormatInt(page, 10)
	}
	if perPage != 0 {
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
	var apiResponse []NFTTradesResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, NFTTradesResponse{
			BuyerAddress:   item.BuyerAddress,
			CollectionName: item.CollectionName,
			Hash:           item.Hash,
			Image:          item.Image,
			Market:         item.Market,
			Name:           item.Name,
			Policy:         item.Policy,
			Price:          item.Price,
			SellerAddress:  item.SellerAddress,
			Time:           item.Time,
			Timeframe:      timeframe,
			SortBy:         sortBy,
			OrderBy:        orderBy, // Renamed from Order
			MinAmount:      minAmount,
			FromTimestamp:  fromTimestamp, // Renamed from From
			Page:           page,
			PerPage:        perPage,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsNFTTrades() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_nft_trades",
		Description: "Get individual trades for a particular collection or for the entire NFT market.",
		List: &plugin.ListConfig{
			Hydrate: listNFTTrades,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "policy", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_by", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "order_by", Require: plugin.Optional, Operators: []string{"="}}, // Renamed from "order"
				{Name: "min_amount", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "from_timestamp", Require: plugin.Optional, Operators: []string{"="}}, // Renamed from "from"
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "buyer_address", Type: proto.ColumnType_STRING, Description: "Address of the buyer"},
			{Name: "collection_name", Type: proto.ColumnType_STRING, Description: "Name of the collection"},
			{Name: "hash", Type: proto.ColumnType_STRING, Description: "Transaction hash of the trade"},
			{Name: "image", Type: proto.ColumnType_STRING, Description: "URL of the NFT's image"},
			{Name: "market", Type: proto.ColumnType_STRING, Description: "Marketplace where the trade occurred"},
			{Name: "name", Type: proto.ColumnType_STRING, Description: "Name of the NFT"},
			{Name: "policy", Type: proto.ColumnType_STRING, Description: "Policy ID of the collection"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Price of the trade"},
			{Name: "seller_address", Type: proto.ColumnType_STRING, Description: "Address of the seller"},
			{Name: "time", Type: proto.ColumnType_INT, Description: "Unix timestamp of the trade"},

			// Query parameters
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=30d The time interval. Options are 1h, 4h, 24h, 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d."},
			{Name: "sort_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortBy"), Description: "Example: sortBy=time What should the results be sorted by. Options are amount, time. Default is time."},
			{Name: "order_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("OrderBy"), Description: "Example: order_by=desc Which direction should the results be sorted. Options are asc, desc. Default is desc."}, // Renamed from "order"
			{Name: "min_amount", Type: proto.ColumnType_INT, Transform: transform.FromField("MinAmount"), Description: "Example: min_amount=1000 Filter to only trades of a certain ADA amount."},
			{Name: "from_timestamp", Type: proto.ColumnType_INT, Transform: transform.FromField("FromTimestamp"), Description: "Example: from_timestamp=1704759422 Filter trades using a UNIX timestamp, will only return trades after this timestamp."}, // Renamed from "from"
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=100 Specify how many items to return per page. Maximum is 100, default is 100."},
		},
	}
}
