$version: "2.0"

namespace com.example.blog

/// A simple blog service demonstrating Smithy code generation
@restJson1
service BlogService {
    version: "2024-01-01"
    operations: [
        CreatePost
        GetPost
        ListPosts
    ]
}

/// Creates a new blog post
@http(method: "POST", uri: "/posts", code: 201)
operation CreatePost {
    input := CreatePostInput
    output := CreatePostOutput
}

/// Retrieves a blog post by ID
@http(method: "GET", uri: "/posts/{id}", code: 200)
operation GetPost {
    input := GetPostInput
    output := GetPostOutput
}

/// Lists all blog posts
@http(method: "GET", uri: "/posts", code: 200)
operation ListPosts {
    input := ListPostsInput
    output := ListPostsOutput
}

/// Input for creating a post
structure CreatePostInput {
    @required
    @length(min: 1, max: 200)
    title: String

    @required
    @length(min: 1, max: 10000)
    content: String

    @required
    author: String

    tags: TagList
}

/// Output from creating a post
structure CreatePostOutput {
    @required
    post: Post
}

/// Input for getting a post
structure GetPostInput {
    @httpLabel
    @required
    id: String
}

/// Output from getting a post
structure GetPostOutput {
    @required
    post: Post
}

/// Input for listing posts
structure ListPostsInput {
    @httpQuery("limit")
    @range(min: 1, max: 100)
    limit: Integer

    @httpQuery("offset")
    @range(min: 0)
    offset: Integer
}

/// Output from listing posts
structure ListPostsOutput {
    @required
    posts: PostList

    totalCount: Integer
}

/// A blog post
structure Post {
    @required
    id: String

    @required
    title: String

    @required
    content: String

    @required
    author: String

    tags: TagList

    @required
    createdAt: Timestamp

    updatedAt: Timestamp
}

list PostList {
    member: Post
}

list TagList {
    member: String
}
