defmodule NervesHubAPIWeb.DeploymentController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.{Deployments, Firmwares}
  alias NervesHubCore.Deployments.Deployment

  action_fallback(NervesHubAPIWeb.FallbackController)

  defp whitelist(params, keys) do
    keys
    |> Enum.filter(fn x -> !is_nil(params[to_string(x)]) end)
    |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
  end

  def index(%{assigns: %{product: product}} = conn, _params) do
    deployments = Deployments.get_deployments_by_product(product.id)
    render(conn, "index.json", deployments: deployments)
  end

  def create(%{assigns: %{org: org, product: product}} = conn, params) do
    case Map.get(params, "firmware") do
      nil ->
        {:error, :no_firmware_uuid}

      uuid ->
        with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid),
             params <- Map.put(params, "firmware_id", firmware.id),
             {:ok, deployment} <-
               Deployments.create_deployment(
                 params
                 |> whitelist([:name, :firmware_id, :conditions, :is_active])
               ) do
          conn
          |> put_status(:created)
          |> put_resp_header(
            "location",
            deployment_path(conn, :show, org.name, product.name, deployment.name)
          )
          |> render("show.json", deployment: %{deployment | firmware: firmware})
        end
    end
  end

  def show(%{assigns: %{org: _org, product: product}} = conn, %{"name" => name}) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name) do
      render(conn, "show.json", deployment: deployment)
    end
  end

  def update(%{assigns: %{product: product, org: org}} = conn, %{
        "name" => name,
        "deployment" => deployment_params
      }) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name),
         {:ok, deployment_params} <- update_params(org, deployment_params),
         {:ok, %Deployment{} = deployment} <-
           Deployments.update_deployment(
             deployment,
             deployment_params
             |> whitelist([:name, :firmware_id, :conditions, :is_active])
           ) do
      render(conn, "show.json", deployment: deployment)
    end
  end

  defp update_params(org, %{"firmware" => uuid} = params) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid) do
      {:ok, Map.put(params, :firmware_id, firmware.id)}
    end
  end

  defp update_params(_, params), do: {:ok, params}
end
