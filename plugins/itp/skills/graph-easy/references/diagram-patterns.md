# Common Diagram Patterns

## Pipeline (Left-to-Right)

```
graph { flow: east; }
[Input] -> [Process] -> [Output]
```

## Multi-Component System

```
graph { flow: south; }
[API Gateway] -> [Service A]
[API Gateway] -> [Service B]
[Service A] -> [Database]
[Service B] -> [Database]
```

## Decision with Options

```
graph { flow: south; }
[Decision] -> [Option A]
[Decision] -> [Option B]
[Decision] -> [Option C]
```

## Grouped Components

```
( Frontend:
  [React App]
  [Vue App]
)
( Backend:
  [API Server]
  [Worker]
)
[React App] -> [API Server]
[Vue App] -> [API Server]
[API Server] -> [Worker]
```

## Bidirectional Flow

```
[Client] <-> [Server]
[Server] -> [Database]
```

## Layered Architecture

```
graph { flow: south; }
( Presentation:
  [UI Components]
)
( Business:
  [Services]
)
( Data:
  [Repository]
  [Database]
)
[UI Components] -> [Services]
[Services] -> [Repository]
[Repository] -> [Database]
```
