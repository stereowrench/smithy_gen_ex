defmodule SmithyGen.IRTest do
  use ExUnit.Case, async: true

  alias SmithyGen.IR
  alias SmithyGen.IR.{Model, Service, Operation, Shape, Member, HttpBinding}

  describe "from_ast/1" do
    test "builds Model from AST with metadata namespace" do
      ast = %{
        "metadata" => %{"namespace" => "com.example"},
        "shapes" => %{
          "com.example#User" => %{
            "type" => "structure",
            "members" => %{}
          }
        }
      }

      assert {:ok, %Model{} = model} = IR.from_ast(ast)
      assert model.namespace == "com.example"
    end

    test "extracts namespace from first shape ID when metadata missing" do
      ast = %{
        "shapes" => %{
          "com.example#User" => %{"type" => "structure", "members" => %{}}
        }
      }

      assert {:ok, model} = IR.from_ast(ast)
      assert model.namespace == "com.example"
    end

    test "returns error when no namespace can be determined" do
      ast = %{"smithy" => "2.0"}
      assert {:error, :namespace_not_found} = IR.from_ast(ast)
    end

    test "returns error for empty shapes map with no metadata namespace" do
      ast = %{"shapes" => %{}}
      # No shapes and no metadata means namespace can't be determined
      assert {:error, _} = IR.from_ast(ast)
    end

    test "stores metadata" do
      ast = %{
        "metadata" => %{"namespace" => "test", "custom" => "value"},
        "shapes" => %{}
      }

      assert {:ok, model} = IR.from_ast(ast)
      assert model.metadata["custom"] == "value"
    end
  end

  describe "shape building" do
    test "builds structure shape with members" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#User" => %{
            "type" => "structure",
            "members" => %{
              "id" => %{"target" => "smithy.api#String", "traits" => %{"smithy.api#required" => %{}}},
              "name" => %{"target" => "smithy.api#String", "traits" => %{}}
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)

      user = model.shapes["test#User"]
      assert %Shape{} = user
      assert user.type == :structure
      assert user.name == "User"
      assert map_size(user.members) == 2

      id_member = user.members["id"]
      assert %Member{} = id_member
      assert id_member.name == "id"
      assert id_member.target == "smithy.api#String"
      assert Map.has_key?(id_member.traits, "smithy.api#required")
    end

    test "builds shape with documentation" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#User" => %{
            "type" => "structure",
            "members" => %{},
            "traits" => %{"smithy.api#documentation" => "A user account"}
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#User"].documentation == "A user account"
    end

    test "builds shape types correctly" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#MyStruct" => %{"type" => "structure", "members" => %{}},
          "test#MyList" => %{"type" => "list", "target" => "smithy.api#String"},
          "test#MyMap" => %{"type" => "map"}
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#MyStruct"].type == :structure
      assert model.shapes["test#MyList"].type == :list
      assert model.shapes["test#MyMap"].type == :map
    end
  end

  describe "member HTTP binding detection" do
    test "detects httpLabel binding" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Input" => %{
            "type" => "structure",
            "members" => %{
              "id" => %{
                "target" => "smithy.api#String",
                "traits" => %{"smithy.api#httpLabel" => %{}}
              }
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#Input"].members["id"].http_binding == :path
    end

    test "detects httpQuery binding" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Input" => %{
            "type" => "structure",
            "members" => %{
              "limit" => %{
                "target" => "smithy.api#Integer",
                "traits" => %{"smithy.api#httpQuery" => "limit"}
              }
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#Input"].members["limit"].http_binding == :query
    end

    test "detects httpHeader binding" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Input" => %{
            "type" => "structure",
            "members" => %{
              "auth" => %{
                "target" => "smithy.api#String",
                "traits" => %{"smithy.api#httpHeader" => "Authorization"}
              }
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#Input"].members["auth"].http_binding == :header
    end

    test "detects httpPayload binding" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Input" => %{
            "type" => "structure",
            "members" => %{
              "body" => %{
                "target" => "smithy.api#Blob",
                "traits" => %{"smithy.api#httpPayload" => %{}}
              }
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#Input"].members["body"].http_binding == :body
    end

    test "returns nil for members without HTTP binding" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Input" => %{
            "type" => "structure",
            "members" => %{
              "name" => %{"target" => "smithy.api#String", "traits" => %{}}
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.shapes["test#Input"].members["name"].http_binding == nil
    end
  end

  describe "service building" do
    test "builds service with operations" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#MyService" => %{
            "type" => "service",
            "version" => "2.0",
            "operations" => ["test#DoThing"],
            "traits" => %{}
          },
          "test#DoThing" => %{
            "type" => "operation",
            "input" => "test#DoThingInput",
            "output" => "test#DoThingOutput",
            "traits" => %{
              "smithy.api#http" => %{"method" => "POST", "uri" => "/things", "code" => 201}
            }
          },
          "test#DoThingInput" => %{"type" => "structure", "members" => %{"name" => %{"target" => "smithy.api#String"}}},
          "test#DoThingOutput" => %{"type" => "structure", "members" => %{"id" => %{"target" => "smithy.api#String"}}}
        }
      }

      {:ok, model} = IR.from_ast(ast)

      assert %Service{} = model.service
      assert model.service.name == "MyService"
      assert model.service.version == "2.0"
      assert length(model.service.operations) == 1

      [op] = model.service.operations
      assert %Operation{} = op
      assert op.name == "DoThing"
      assert op.input.name == "DoThingInput"
      assert op.output.name == "DoThingOutput"
    end

    test "returns nil service when no service shape exists" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#User" => %{"type" => "structure", "members" => %{}}
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.service == nil
    end
  end

  describe "HTTP binding extraction" do
    test "extracts method, uri, and code from http trait" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Svc" => %{
            "type" => "service",
            "version" => "1.0",
            "operations" => ["test#GetItem"]
          },
          "test#GetItem" => %{
            "type" => "operation",
            "traits" => %{
              "smithy.api#http" => %{"method" => "GET", "uri" => "/items/{id}", "code" => 200}
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      [op] = model.service.operations

      assert %HttpBinding{} = op.http
      assert op.http.method == "GET"
      assert op.http.uri == "/items/{id}"
      assert op.http.code == 200
    end

    test "extracts path parameters from URI" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Svc" => %{"type" => "service", "version" => "1.0", "operations" => ["test#Get"]},
          "test#Get" => %{
            "type" => "operation",
            "traits" => %{
              "smithy.api#http" => %{"method" => "GET", "uri" => "/buckets/{bucket}/items/{key+}"}
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      [op] = model.service.operations

      assert op.http.path_params == ["bucket", "key"]
    end

    test "defaults to POST / when no http trait" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Svc" => %{"type" => "service", "version" => "1.0", "operations" => ["test#Op"]},
          "test#Op" => %{"type" => "operation"}
        }
      }

      {:ok, model} = IR.from_ast(ast)
      [op] = model.service.operations

      assert op.http.method == "POST"
      assert op.http.uri == "/"
      assert op.http.code == 200
    end
  end

  describe "protocol detection" do
    test "detects restJson1" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Svc" => %{
            "type" => "service",
            "version" => "1.0",
            "operations" => [],
            "traits" => %{"aws.protocols#restJson1" => %{}}
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.service.protocol == :restJson1
    end

    test "detects awsJson1_0" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Svc" => %{
            "type" => "service",
            "version" => "1.0",
            "operations" => [],
            "traits" => %{"aws.protocols#awsJson1_0" => %{}}
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.service.protocol == :awsJson1_0
    end

    test "defaults to restJson1 when no protocol trait" do
      ast = %{
        "metadata" => %{"namespace" => "test"},
        "shapes" => %{
          "test#Svc" => %{"type" => "service", "version" => "1.0", "operations" => []}
        }
      }

      {:ok, model} = IR.from_ast(ast)
      assert model.service.protocol == :restJson1
    end
  end
end
