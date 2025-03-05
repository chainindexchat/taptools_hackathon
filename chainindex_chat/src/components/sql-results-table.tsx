"use client"

import { useState } from "react"
import { ChevronDown, ChevronUp, ChevronsUpDown, Code, FileText } from "lucide-react"
import { Button } from "@workspace/ui/components/button"
import { Card } from "@workspace/ui/components/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@workspace/ui/components/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@workspace/ui/components/table"
import { cn } from "@/lib/utils"

type SortDirection = "asc" | "desc" | null

interface SqlResultsTableProps {
  data: Record<string, any>[]
  queryDescription: string
  sqlStatement: string
}

export default function SqlResultsTable({ data, queryDescription, sqlStatement }: SqlResultsTableProps) {
  const [sortColumn, setSortColumn] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<SortDirection>(null)
  const [currentPage, setCurrentPage] = useState(1)
  const rowsPerPage = 10

  // Get all unique columns from the data
  const columns = data.length > 0 ? Object.keys(data[0]) : []

  // Handle sorting
  const handleSort = (column: string) => {
    if (sortColumn === column) {
      // Toggle direction if same column
      if (sortDirection === "asc") {
        setSortDirection("desc")
      } else if (sortDirection === "desc") {
        setSortDirection(null)
        setSortColumn(null)
      } else {
        setSortDirection("asc")
      }
    } else {
      // New column, set to ascending
      setSortColumn(column)
      setSortDirection("asc")
    }
  }

  // Sort the data
  const sortedData = [...data].sort((a, b) => {
    if (!sortColumn || !sortDirection) return 0

    const aValue = a[sortColumn]
    const bValue = b[sortColumn]

    // Handle different data types
    if (typeof aValue === "number" && typeof bValue === "number") {
      return sortDirection === "asc" ? aValue - bValue : bValue - aValue
    }

    // Convert to string for comparison
    const aString = String(aValue || "")
    const bString = String(bValue || "")

    return sortDirection === "asc" ? aString.localeCompare(bString) : bString.localeCompare(aString)
  })

  // Pagination
  const totalPages = Math.ceil(sortedData.length / rowsPerPage)
  const paginatedData = sortedData.slice((currentPage - 1) * rowsPerPage, currentPage * rowsPerPage)

  // Format cell value for display
  const formatCellValue = (value: any) => {
    if (value === null || value === undefined) return "NULL"
    if (typeof value === "boolean") return value ? "true" : "false"
    if (value instanceof Date) return value.toLocaleString()
    return String(value)
  }

  return (
    <div className="space-y-4">
      <Tabs defaultValue="description" className="w-full">
        <TabsList>
          <TabsTrigger value="description" className="flex items-center gap-2">
            <FileText className="h-4 w-4" />
            Description
          </TabsTrigger>
          <TabsTrigger value="sql" className="flex items-center gap-2">
            <Code className="h-4 w-4" />
            SQL Query
          </TabsTrigger>
        </TabsList>
        <TabsContent value="description" className="mt-2">
          <Card className="p-4">
            <p>{queryDescription}</p>
          </Card>
        </TabsContent>
        <TabsContent value="sql" className="mt-2">
          <Card className="p-4">
            <pre className="bg-muted p-4 rounded-md overflow-x-auto">
              <code className="text-sm font-mono">{sqlStatement}</code>
            </pre>
          </Card>
        </TabsContent>
      </Tabs>

      <div className="rounded-md border">
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                {columns.map((column) => (
                  <TableHead key={column} className="whitespace-nowrap">
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-8 px-2 font-medium flex items-center gap-1"
                      onClick={() => handleSort(column)}
                    >
                      {column}
                      {sortColumn === column ? (
                        sortDirection === "asc" ? (
                          <ChevronUp className="h-4 w-4" />
                        ) : (
                          <ChevronDown className="h-4 w-4" />
                        )
                      ) : (
                        <ChevronsUpDown className="h-4 w-4 opacity-50" />
                      )}
                    </Button>
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {paginatedData.length > 0 ? (
                paginatedData.map((row, rowIndex) => (
                  <TableRow key={rowIndex} className={rowIndex % 2 === 0 ? "bg-muted/50" : ""}>
                    {columns.map((column) => (
                      <TableCell key={`${rowIndex}-${column}`} className="whitespace-nowrap">
                        {formatCellValue(row[column])}
                      </TableCell>
                    ))}
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={columns.length} className="h-24 text-center">
                    No results found.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </div>
      </div>

      {/* Pagination controls */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <div className="text-sm text-muted-foreground">
            Showing {(currentPage - 1) * rowsPerPage + 1} to {Math.min(currentPage * rowsPerPage, sortedData.length)} of{" "}
            {sortedData.length} results
          </div>
          <div className="flex items-center space-x-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
              disabled={currentPage === 1}
            >
              Previous
            </Button>
            <div className="flex items-center gap-1">
              {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                // Show pages around current page
                let pageNum = i + 1
                if (totalPages > 5) {
                  if (currentPage > 3) {
                    pageNum = currentPage - 3 + i
                  }
                  if (currentPage > totalPages - 2) {
                    pageNum = totalPages - 4 + i
                  }
                }

                return pageNum <= totalPages ? (
                  <Button
                    key={pageNum}
                    variant={currentPage === pageNum ? "default" : "outline"}
                    size="sm"
                    className={cn("h-8 w-8 p-0", currentPage === pageNum && "pointer-events-none")}
                    onClick={() => setCurrentPage(pageNum)}
                  >
                    {pageNum}
                  </Button>
                ) : null
              })}
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
              disabled={currentPage === totalPages}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

