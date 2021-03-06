defmodule NervesHubAPIWeb.Router do
  use NervesHubAPIWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :user do
    plug(NervesHubAPIWeb.Plugs.User)
  end

  pipeline :org do
    plug(NervesHubAPIWeb.Plugs.Org)
  end

  pipeline :product do
    plug(NervesHubAPIWeb.Plugs.Product)
  end

  scope "/users", NervesHubAPIWeb do
    pipe_through(:api)

    post("/register", UserController, :register)
    post("/auth", UserController, :auth)
    post("/sign", UserController, :sign)
  end

  scope "/", NervesHubAPIWeb do
    pipe_through(:api)
    pipe_through(:user)

    scope "/users" do
      get("/me", UserController, :me)
    end

    scope "/orgs" do
      scope "/:org_name" do
        pipe_through(:org)

        scope "/keys" do
          get("/", KeyController, :index)
          post("/", KeyController, :create)
          get("/:name", KeyController, :show)
          delete("/:name", KeyController, :delete)
        end

        scope "/devices" do
          post("/", DeviceController, :create)

          scope "/:device_identifier" do
            get("/", DeviceController, :show)
            delete("/", DeviceController, :delete)

            scope "/certificates" do
              get("/", DeviceCertificateController, :index)
              post("/sign", DeviceCertificateController, :sign)
            end
          end
        end

        scope "/products" do
          get("/", ProductController, :index)
          post("/", ProductController, :create)

          scope "/:product_name" do
            pipe_through(:product)

            get("/", ProductController, :show)
            delete("/", ProductController, :delete)
            put("/", ProductController, :update)

            scope "/firmwares" do
              get("/", FirmwareController, :index)
              get("/:uuid", FirmwareController, :show)
              post("/", FirmwareController, :create)
              delete("/:uuid", FirmwareController, :delete)
            end

            scope "/deployments" do
              get("/", DeploymentController, :index)
              post("/", DeploymentController, :create)
              get("/:name", DeploymentController, :show)
              put("/:name", DeploymentController, :update)
            end
          end
        end
      end
    end
  end
end
