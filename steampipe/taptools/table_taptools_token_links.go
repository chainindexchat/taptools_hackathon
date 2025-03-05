package taptools

import (
	"context"
	"fmt"
	"io"

	"encoding/json"
	"net/http"
	"os"

	"github.com/turbot/steampipe-plugin-sdk/v5/grpc/proto"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin"
	"github.com/turbot/steampipe-plugin-sdk/v5/plugin/transform"
)

func tableTaptoolsTokenLinks() *plugin.Table {
	return &plugin.Table{
		Name:        "taptools_token_links",
		Description: "Get a specific token's social links, if they have been provided to TapTools.",
		List: &plugin.ListConfig{
			Hydrate: listTokenLinks,
			KeyColumns: plugin.KeyColumnSlice{
				{Name: "unit", Require: plugin.Optional, Operators: []string{"="}},
			},
		},
		Columns: []*plugin.Column{
			// Response properties
			{Name: "description", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "discord", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "email", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "facebook", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "github", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "instagram", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "medium", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "reddit", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "telegram", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "twitter", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "website", Type: proto.ColumnType_STRING, Description: ""},
			{Name: "youtube", Type: proto.ColumnType_STRING, Description: ""},

			// Query parameters
			{Name: "unit", Type: proto.ColumnType_STRING, Transform: transform.FromField("Unit"), Description: "Example: unit=8fef2d34078659493ce161a6c7fba4b56afefa8535296a5743f6958741414441 Token unit (policy + hex name)"},
		},
	}
}

// Define the structure for the API response
type TokenLinksResponse struct {
	Description string `json:"description"`
	Discord     string `json:"discord"`
	Email       string `json:"email"`
	Facebook    string `json:"facebook"`
	Github      string `json:"github"`
	Instagram   string `json:"instagram"`
	Medium      string `json:"medium"`
	Reddit      string `json:"reddit"`
	Telegram    string `json:"telegram"`
	Twitter     string `json:"twitter"`
	Website     string `json:"website"`
	Youtube     string `json:"youtube"`
	Unit        string `json:"unit,omitempty"`
}

func listTokenLinks(ctx context.Context, d *plugin.QueryData, _ *plugin.HydrateData) (interface{}, error) {

	TAPTOOLS_API_KEY := os.Getenv("TAPTOOLS_API_KEY")
	if TAPTOOLS_API_KEY == "" {
		return nil, fmt.Errorf("TAPTOOLS_API_KEY environment variable is not set")
	}

	// Get query parameters from the query context
	var unit string
	if quals := d.Quals["unit"]; quals != nil && len(quals.Quals) > 0 {
		unit = quals.Quals[0].Value.GetStringValue()
	}

	// Check if unit is provided
	if unit == "" {
		return nil, fmt.Errorf("unit must be provided")
	}

	// URL for the API endpoint with proper escaping
	reqUrl := fmt.Sprintf("https://openapi.taptools.io/api/v1/token/links?unit=%s", unit)

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
	var apiResponse TokenLinksResponse
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("error unmarshalling JSON: %v, response: %s", err, string(body))
	}

	// Stream the item to Steampipe with the unit metadata
	d.StreamListItem(ctx, TokenLinksResponse{
		Description: apiResponse.Description,
		Discord:     apiResponse.Discord,
		Email:       apiResponse.Email,
		Facebook:    apiResponse.Facebook,
		Github:      apiResponse.Github,
		Instagram:   apiResponse.Instagram,
		Medium:      apiResponse.Medium,
		Reddit:      apiResponse.Reddit,
		Telegram:    apiResponse.Telegram,
		Twitter:     apiResponse.Twitter,
		Website:     apiResponse.Website,
		Youtube:     apiResponse.Youtube,
		Unit:        unit,
	})

	return nil, nil
}
