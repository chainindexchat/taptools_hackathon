package taptools

import (
	"context"
	"fmt"
	"io"
	"strconv"

	"encoding/json"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

func tableTaptoolsTokenActiveLoans() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_active_loans",
		Description: "Get active P2P loans of a certain token (Currently only supports P2P protocols like Lenfi and Levvy).",
		List: &plugin.ListConfig{
			Hydrate: listTokenActiveLoans,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "include", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_by", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "sort_order", Require: plugin.Optional, Operators: []string{"="}}, // Renamed from "order"
				{Name: "page", Require: plugin.Optional, Operators: []string{"="}},
				{Name: "per_page", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "collateral_amount", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "collateral_token", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "collateral_value", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "debt_amount", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "debt_token", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "debt_value", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "expiration", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "hash", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "health", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "interest_amount", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "interest_token", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "interest_value", Type: proto.ColumnType_DOUBLE, Description: ""},
			{Name: "protocol", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "time", Type: proto.ColumnType_INT, Description: ""},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
			{Name: "include", Type: proto.ColumnType_STRING, Transform: transform.FromField("Include"), Description: "Example: include=collateral,debt Comma separated value enabling you to filter to loans where token is used as collateral, debt, interest or a mix of them, default is collateral,debt filtering to loans where token is used as collateral OR debt."},
			{Name: "sort_by", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortBy"), Description: "Example: sortBy=time What should the results be sorted by. Options are time, expiration. Default is time. expiration is expiration date of loan."},
			{Name: "sort_order", Type: proto.ColumnType_STRING, Transform: transform.FromField("SortOrder"), Description: "Example: sort_order=desc Which direction should the results be sorted. Options are asc, desc. Default is desc."}, // Renamed from "order"
			{Name: "page", Type: proto.ColumnType_INT, Transform: transform.FromField("Page"), Description: "Example: page=1 This endpoint supports pagination. Default page is 1."},
			{Name: "per_page", Type: proto.ColumnType_INT, Transform: transform.FromField("PerPage"), Description: "Example: perPage=100 Specify how many items to return per page, default is 100."},
		},
	}
}

// Define the structure for the API response
type TokenActiveLoansResponse struct {
	CollateralAmount float64 `json:"collateralAmount"`
	CollateralToken  string  `json:"collateralToken"`
	CollateralValue  float64 `json:"collateralValue"`
	DebtAmount       float64 `json:"debtAmount"`
	DebtToken        string  `json:"debtToken"`
	DebtValue        float64 `json:"debtValue"`
	Expiration       float64 `json:"expiration"`
	Hash             string  `json:"hash"`
	Health           float64 `json:"health"`
	InterestAmount   float64 `json:"interestAmount"`
	InterestToken    string  `json:"interestToken"`
	InterestValue    float64 `json:"interestValue"`
	Protocol         string  `json:"protocol"`
	Time             int64   `json:"time"`

	Unit      string `json:"unit,omitempty"`
	Include   string `json:"include,omitempty"`
	SortBy    string `json:"sortBy,omitempty"`
	SortOrder string `json:"sortOrder,omitempty"` // Renamed from "Order"
	Page      int64  `json:"page,omitempty"`
	PerPage   int64  `json:"perPage,omitempty"`
}

func listTokenActiveLoans(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var unit, include, sortBy, sortOrder string // Renamed "order" to "sortOrder"
	var page, perPage int64 = 1, 100            // Default values

	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["include"]; quals != nil && len(quals.Quals) > 0 {
		include = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_by"]; quals != nil && len(quals.Quals) > 0 {
		sortBy = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["sort_order"]; quals != nil && len(quals.Quals) > 0 { // Renamed from "order"
		sortOrder = quals.Quals[0].Value.GetStringValue()
	}
	if quals := d.Quals["page"]; quals != nil && len(quals.Quals) > 0 {
		page = quals.Quals[0].Value.GetInt64Value()
	}
	if quals := d.Quals["per_page"]; quals != nil && len(quals.Quals) > 0 {
		perPage = quals.Quals[0].Value.GetInt64Value()
	}

	// Check if unit is provided
	if unit == "" {
		return nil, fmt.Errorf("unit must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/active-loans?unit=%s", unit) // Corrected endpoint from "token/debt/loans" to "token/active-loans"
	if include != "" {
		reqUrl += "&include=" + include
	}
	if sortBy != "" {
		reqUrl += "&sortBy=" + sortBy
	}
	if sortOrder != "" { // Renamed from "order"
		reqUrl += "&order=" + sortOrder // API still expects "order" as the parameter name
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
	var apiResponse []TokenActiveLoansResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the items to Steampipe with additional metadata
	for _, item := range apiResponse {
		d.StreamListItem(ctx, TokenActiveLoansResponse{
			CollateralAmount: item.CollateralAmount,
			CollateralToken:  item.CollateralToken,
			CollateralValue:  item.CollateralValue,
			DebtAmount:       item.DebtAmount,
			DebtToken:        item.DebtToken,
			DebtValue:        item.DebtValue,
			Expiration:       item.Expiration,
			Hash:             item.Hash,
			Health:           item.Health,
			InterestAmount:   item.InterestAmount,
			InterestToken:    item.InterestToken,
			InterestValue:    item.InterestValue,
			Protocol:         item.Protocol,
			Time:             item.Time,
			Unit:             unit,
			Include:          include,
			SortBy:           sortBy,
			SortOrder:        sortOrder, // Renamed from "Order"
			Page:             page,
			PerPage:          perPage,
		})

		// Check if we need to stop due to LIMIT being reached
		if d.RowsRemaining(ctx) == 0 {
			break
		}
	}

	return nil, nil
}
