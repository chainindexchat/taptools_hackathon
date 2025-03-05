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
type TokenTradeResponse struct {
	Action       string  `json:"action"`
	Address      string  `json:"address"`
	Exchange     string  `json:"exchange"`
	Hash         string  `json:"hash"`
	LpTokenUnit  string  `json:"lpTokenUnit"`
	Price        float64 `json:"price"`
	Time         int64   `json:"time"`
	TokenA       string  `json:"tokenA"`
	TokenAAmount float64 `json:"tokenAAmount"`
	TokenAName   string  `json:"tokenAName"`
	TokenB       string  `json:"tokenB"`
	TokenBAmount float64 `json:"tokenBAmount"`
	TokenBName   string  `json:"tokenBName"`

	Timeframe     string `json:"timeframe,omitempty"`
	SortBy        string `json:"sortBy,omitempty"`
	SortOrder     string `json:"sorOrder,omitempty"`
	Unit          string `json:"unit,omitempty"`
	MinAmount     int64  `json:"minAmount,omitempty"`
	FromTimestamp int64  `json:"fromTimestamp,omitempty"`
	Page          int64  `json:"page,omitempty"`
	PerPage       int64  `json:"perPage,omitempty"`
}

func listTokenTrades(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var timeframe, sortBy, sortOrder, unit string
	var minAmount, fromTimestamp, page, perPage int64

	if quals := d.Quals["timeframe"]; quals != nil && len(quals.Quals) > 0 {
		timeframe = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_by"]; quals != nil && len(quals.Quals) > 0 {
		sortBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_order"]; quals != nil && len(quals.Quals) > 0 {
		sortOrder = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["min_amount"]; quals != nil && len(quals.Quals) > 0 {
		minAmount = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["from_timestamp"]; quals != nil && len(quals.Quals) > 0 {
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
	reqUrl := "https://openapi.taptools.io/api/v1/token/trades"
	if timeframe != "" {
		reqUrl += "?timeframe=" + timeframe
	}
	if sortBy != "" {
		reqUrl += "&sortBy=" + sortBy
	}
	if sortOrder != "" {
		reqUrl += "&order=" + sortOrder
	}
	if unit != "" {
		reqUrl += "&unit=" + unit
	}
	if minAmount != 0 {
		reqUrl += "&minAmount=" + strconv.FormatInt(minAmount, 10)
	}
	if fromTimestamp != 0 {
		reqUrl += "&from=" + strconv.FormatInt(fromTimestamp, 10)
	}
	if page != 1 {
		reqUrl += "&page=" + strconv.FormatInt(page, 10)
	}
	if perPage != 10 {
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
	var apiResponse []TokenTradeResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TokenTradeResponse{
			Action:        item.Action,
			Address:       item.Address,
			Exchange:      item.Exchange,
			Hash:          item.Hash,
			LpTokenUnit:   item.LpTokenUnit,
			Price:         item.Price,
			Time:          item.Time,
			TokenA:        item.TokenA,
			TokenAAmount:  item.TokenAAmount,
			TokenAName:    item.TokenAName,
			TokenB:        item.TokenB,
			TokenBAmount:  item.TokenBAmount,
			TokenBName:    item.TokenBName,
			Timeframe:     timeframe,
			SortBy:        sortBy,
			SortOrder:     sortOrder,
			Unit:          unit,
			MinAmount:     minAmount,
			FromTimestamp: fromTimestamp,
			Page:          page,
			PerPage:       perPage,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsTokenTrades() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_trades",
		Description: "Get token trades across the entire DEX market.",
		List: &plugin.ListConfig{
			Hydrate: listTokenTrades,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "timeframe", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_by", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_order", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "min_amount", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "from_timestamp", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "action", Type: proto.ColumnType_STRING, Description: "Action of the trade"},
			{Name: "address", Type: proto.ColumnType_STRING, Description: "Address involved in the trade"},
			{Name: "exchange", Type: proto.ColumnType_STRING, Description: "Exchange where the trade occurred"},
			{Name: "hash", Type: proto.ColumnType_STRING, Description: "Hash of the trade transaction"},
			{Name: "lp_token_unit", Type: proto.ColumnType_STRING, Description: "Unit of the liquidity pool token"},
			{Name: "price", Type: proto.ColumnType_DOUBLE, Description: "Price of the trade"},
			{Name: "time", Type: proto.ColumnType_INT, Description: "Unix timestamp of the trade"},
			{Name: "token_a", Type: proto.ColumnType_STRING, Description: "Token A in the trade"},
			{Name: "token_a_amount", Type: proto.ColumnType_DOUBLE, Description: "Amount of token A traded"},
			{Name: "token_a_name", Type: proto.ColumnType_STRING, Description: "Name of token A"},
			{Name: "token_b", Type: proto.ColumnType_STRING, Description: "Token B in the trade"},
			{Name: "token_b_amount", Type: proto.ColumnType_DOUBLE, Description: "Amount of token B traded"},
			{Name: "token_b_name", Type: proto.ColumnType_STRING, Description: "Name of token B"},

			// Query parameters
			{Name: "timeframe", Type: proto.ColumnType_STRING, Transform: transform.FromField("Timeframe"), Description: "Example: timeframe=30d The time interval. Options are 1h, 4h, 24h, 7d, 30d, 90d, 180d, 1y, all. Defaults to 30d."},
			{Name: "sort_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortBy"), Description: "Example: sortBy=amount What should the results be sorted by. Options are amount, time. Default is amount. Filters to only ADA trades if set to amount."},
			{Name: "sort_order", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortOrder"), Description: "Example: sort_order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc."},
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=279c909f348e533da5808898f87f9a14bb2c3dfbbacccd631d927a3f534e454b Optionally filter to a specific token by specifying a token unit (policy + hex name)."},
			{Name: "min_amount", Type: proto.ColumnType_INT, Transform: transform.FromField("MinAmount"), Description: "Example: minAmount=1000 Filter to only trades of a certain ADA amount."},
			{Name: "from_timestamp", Type: proto.ColumnType_INT, Transform: transform.FromField("FromTimestamp"), Description: "Example: from_timestamp=1704759422 Filter trades using a UNIX timestamp, will only return trades after this timestamp."},
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=10 Specify how many items to return per page. Maximum is 100, default is 10."},
		},
	}
}
