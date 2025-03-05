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
type TokenLiquidityPoolResponse struct {
	Exchange     string  `json:"exchange"`
	LpTokenUnit  string  `json:"lpTokenUnit"`
	OnchainID    string  `json:"onchainID"`
	TokenA       string  `json:"tokenA"`
	TokenALocked float64 `json:"tokenALocked"`
	TokenATicker string  `json:"tokenATicker"`
	TokenB       string  `json:"tokenB"`
	TokenBLocked float64 `json:"tokenBLocked"`
	TokenBTicker string  `json:"tokenBTicker"`

	Unit string `json:"unit,omitempty"`

	AdaOnly int64 `json:"adaOnly,omitempty"`
}

func listTokenLiquidityPools(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var unit, onchainID string
	var adaOnly int64

	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["onchain_id"]; quals != nil && len(quals.Quals) > 0 {
		onchainID = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["ada_only"]; quals != nil && len(quals.Quals) > 0 {
		adaOnly = quals.Quals[0].Value.GetInt64Value()
	}

	// Ensure unit or onchainID is provided
	if unit == "" && onchainID == "" {
		return nil, fmt.Errorf("either unit or onchain_id must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := "https://openapi.taptools.io/api/v1/token/pools"
	if unit != "" {
		reqUrl += "?unit=" + unit
	}
	if onchainID != "" {
		if unit != "" {
			reqUrl += "&onchainID=" + onchainID
		} else {
			reqUrl += "?onchainID=" + onchainID
		}
	}
	if adaOnly > 0 {
		reqUrl += "&adaOnly=" + strconv.FormatInt(adaOnly, 10)
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
	var apiResponse []TokenLiquidityPoolResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TokenLiquidityPoolResponse{
			Exchange:     item.Exchange,
			LpTokenUnit:  item.LpTokenUnit,
			OnchainID:    item.OnchainID,
			TokenA:       item.TokenA,
			TokenALocked: item.TokenALocked,
			TokenATicker: item.TokenATicker,
			TokenB:       item.TokenB,
			TokenBLocked: item.TokenBLocked,
			TokenBTicker: item.TokenBTicker,
			Unit:         unit,

			AdaOnly: adaOnly,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}

func tableTaptoolsTokenLiquidityPools() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_liquidity_pools",
		Description: "Get a specific token's active liquidity pools. Can search for all token pools using unit or can search for specific pool with onchainID.",
		List: &plugin.ListConfig{
			Hydrate: listTokenLiquidityPools,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "onchain_id", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "ada_only", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "exchange", Type: proto.ColumnType_STRING, Description: "The exchange where the liquidity pool is"},
			{Name: "lp_token_unit", Type: proto.ColumnType_STRING, Description: "Unit of the liquidity pool token"},
			// {Name: "onchain_id", Type: proto.ColumnType_STRING, Description: "OnchainID of the liquidity pool"},
			{Name: "token_a", Type: proto.ColumnType_STRING, Description: "Unit of token A in the pool"},
			{Name: "token_a_locked", Type: proto.ColumnType_DOUBLE, Description: "Amount of token A locked in the pool"},
			{Name: "token_a_ticker", Type: proto.ColumnType_STRING, Description: "Ticker for token A"},
			{Name: "token_b", Type: proto.ColumnType_STRING, Description: "Unit of token B in the pool"},
			{Name: "token_b_locked", Type: proto.ColumnType_DOUBLE, Description: "Amount of token B locked in the pool"},
			{Name: "token_b_ticker", Type: proto.ColumnType_STRING, Description: "Ticker for token B"},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
			{Name: "onchain_id", Type: proto.ColumnType_STRING, Transform: transform.FromField("Onchain"), Description: "Example: onchainID=0be55d262b29f564998ff81efe21bdc0022621c12f15af08d0f2ddb1.39b9b709ac8605fc82116a2efc308181ba297c11950f0f350001e28f0e50868b Liquidity pool onchainID"},
			{Name: "ada_only", Type: proto.ColumnType_INT, Transform: transform.FromField("AdaOnly"), Description: "Example: adaOnly=1 Return only ADA pools or all pools (0, 1)"},
		},
	}
}
