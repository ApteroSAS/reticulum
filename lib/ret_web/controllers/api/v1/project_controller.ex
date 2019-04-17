defmodule RetWeb.Api.V1.ProjectController do
  use RetWeb, :controller

  alias Ret.{Project, Scene, Repo, Storage}

  # Limit to 1 TPS
  plug(RetWeb.Plugs.RateLimit when action in [:create])

  def index(conn, %{} = _params) do
    account = Guardian.Plug.current_resource(conn)
    projects = Project.projects_for_account(account)
    render(conn, "index.json", projects: projects)
  end

  def show(conn, %{"id" => project_sid}) do
    account = Guardian.Plug.current_resource(conn)

    case Project.project_by_sid_for_account(project_sid, account) do
      %Project{} = project -> render(conn, "show.json", project: project)
      nil -> render_error_json(conn, :not_found)
    end
  end

  def create(conn, %{"project" => params}) do
    account = Guardian.Plug.current_resource(conn)

    case Project.create_project(account, params) do
      {:ok, project} -> render(conn, "show.json", project: project)
      {:error, error} -> render_error_json(conn, error)
    end
  end

  def publish(conn, %{"project_id" => project_sid, "scene" => params}) do
    account = Guardian.Plug.current_resource(conn)

    promotion_params = %{
      model: {params["model_file_id"], params["model_file_token"]},
      screenshot: {params["screenshot_file_id"], params["screenshot_file_token"]}
    }

    with %Project{} = project <- Project.project_by_sid_for_account(project_sid, account),
         %{model: {:ok, model_owned_file}, screenshot: {:ok, screenshot_owned_file}} <- Storage.promote(promotion_params, account),
         {:ok, scene} <- Scene.publish(account, project, model_owned_file, screenshot_owned_file, params) do
      conn
      |> put_view(RetWeb.Api.V1.SceneView)
      |> render("show.json", scene: scene)
    else
      nil -> render_error_json(conn, :not_found)
      {:error, error} -> render_error_json(conn, error)
    end
  end

  def update(conn, %{"id" => project_sid, "project" => params}) do
    account = Guardian.Plug.current_resource(conn)

    promotion_params = %{
      project: {params["project_file_id"], params["project_file_token"]},
      thumbnail: {params["thumbnail_file_id"], params["thumbnail_file_token"]},
    }

    with %Project{} = project <- Project.project_by_sid_for_account(project_sid, account),
         %{project: {:ok, project_file}, thumbnail: {:ok, thumbnail_file}} <- Storage.promote(promotion_params, account),
         {:ok, project} <- project |> Project.changeset(account, project_file, thumbnail_file, params) |> Repo.update() do
      project = Repo.preload(project, [:project_owned_file, :thumbnail_owned_file])
      render(conn, "show.json", project: project)
    else
      {:error, error} -> render_error_json(conn, error)
      nil -> render_error_json(conn, :not_found)
    end
  end

  def delete(conn, %{"id" => project_sid }) do
    account = Guardian.Plug.current_resource(conn)

    with %Project{} = project <- Project.project_by_sid_for_account(project_sid, account),
         {:ok, _} <- Repo.delete(project) do
      send_resp(conn, 200, "OK")
    else
      {:error, error} -> render_error_json(conn, error)
      nil -> render_error_json(conn, :not_found)
    end
  end
end
