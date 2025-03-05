import { Button } from "@workspace/ui/components/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@workspace/ui/components/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@workspace/ui/components/tabs"

export default function ThemeDemo() {
  return (
    <div className="container mx-auto space-y-10">
      <div className="space-y-2">
        <h1 className="text-4xl font-bold">Ubuntu Theme</h1>
        <p className="text-muted-foreground">A modern theme with Ubuntu font and a vibrant color palette</p>
      </div>

      <Tabs defaultValue="light" className="w-full">
        <TabsList className="grid w-full max-w-md grid-cols-2">
          <TabsTrigger value="light">Light Mode</TabsTrigger>
          <TabsTrigger value="dark">Dark Mode</TabsTrigger>
        </TabsList>
        <TabsContent value="light" className="mt-4 space-y-8">
          <ColorPalette />
          <TypographyDemo />
          <ComponentsDemo />
        </TabsContent>
        <TabsContent value="dark" className="mt-4 space-y-8">
          <div className="rounded-lg bg-background p-6 dark">
            <ColorPalette />
            <TypographyDemo />
            <ComponentsDemo />
          </div>
        </TabsContent>
      </Tabs>
    </div>
  )
}

function ColorPalette() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Color Palette</CardTitle>
        <CardDescription>The primary colors used in this theme</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <ColorSwatch name="Primary" className="bg-primary text-primary-foreground" />
          <ColorSwatch name="Secondary" className="bg-secondary text-secondary-foreground" />
          <ColorSwatch name="Accent" className="bg-accent text-accent-foreground" />
          <ColorSwatch name="Destructive" className="bg-destructive text-destructive-foreground" />
          <ColorSwatch name="Muted" className="bg-muted text-muted-foreground" />
          <ColorSwatch name="Card" className="bg-card text-card-foreground border" />
          <ColorSwatch name="Background" className="bg-background text-foreground border" />
          <ColorSwatch name="Popover" className="bg-popover text-popover-foreground border" />
        </div>
      </CardContent>
    </Card>
  )
}

function ColorSwatch({ name, className }: { name: string; className: string }) {
  return (
    <div className="space-y-1.5">
      <div className={`h-16 rounded-md flex items-center justify-center font-medium ${className}`}>{name}</div>
      <div className="text-xs">{name}</div>
    </div>
  )
}

function TypographyDemo() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Typography</CardTitle>
        <CardDescription>Ubuntu font family with various weights</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <h1 className="text-4xl font-bold">Heading 1</h1>
          <p className="text-sm text-muted-foreground">font-family: Ubuntu; font-weight: 700; font-size: 2.5rem</p>
        </div>
        <div>
          <h2 className="text-3xl font-semibold">Heading 2</h2>
          <p className="text-sm text-muted-foreground">font-family: Ubuntu; font-weight: 600; font-size: 1.875rem</p>
        </div>
        <div>
          <h3 className="text-2xl font-medium">Heading 3</h3>
          <p className="text-sm text-muted-foreground">font-family: Ubuntu; font-weight: 500; font-size: 1.5rem</p>
        </div>
        <div>
          <p className="text-base">Body text looks like this</p>
          <p className="text-sm text-muted-foreground">font-family: Ubuntu; font-weight: 400; font-size: 1rem</p>
        </div>
        <div>
          <p className="text-sm">Small text looks like this</p>
          <p className="text-sm text-muted-foreground">font-family: Ubuntu; font-weight: 400; font-size: 0.875rem</p>
        </div>
      </CardContent>
    </Card>
  )
}

function ComponentsDemo() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Components</CardTitle>
        <CardDescription>UI components with the theme applied</CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="space-y-2">
          <p className="text-sm font-medium">Buttons</p>
          <div className="flex flex-wrap gap-2">
            <Button>Default</Button>
            <Button variant="secondary">Secondary</Button>
            <Button variant="destructive">Destructive</Button>
            <Button variant="outline">Outline</Button>
            <Button variant="ghost">Ghost</Button>
            <Button variant="link">Link</Button>
          </div>
        </div>

        <div className="space-y-2">
          <p className="text-sm font-medium">Cards</p>
          <div className="grid gap-4 sm:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>Card Title</CardTitle>
                <CardDescription>Card description goes here</CardDescription>
              </CardHeader>
              <CardContent>
                <p>Card content and information.</p>
              </CardContent>
              <CardFooter>
                <Button size="sm">Action</Button>
              </CardFooter>
            </Card>
            <Card>
              <CardHeader>
                <CardTitle>Another Card</CardTitle>
                <CardDescription>With different content</CardDescription>
              </CardHeader>
              <CardContent>
                <p>More information can go here.</p>
              </CardContent>
              <CardFooter className="flex justify-between">
                <Button variant="ghost" size="sm">
                  Cancel
                </Button>
                <Button size="sm">Submit</Button>
              </CardFooter>
            </Card>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

