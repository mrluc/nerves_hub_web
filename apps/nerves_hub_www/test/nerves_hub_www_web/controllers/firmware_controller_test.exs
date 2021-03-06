defmodule NervesHubWWWWeb.FirmwareControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser

  alias NervesHubCore.Fixtures

  describe "index" do
    test "lists all firmwares", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org)

      conn = get(conn, product_firmware_path(conn, :index, product.id))
      assert html_response(conn, 200) =~ "Firmware"
      assert html_response(conn, 200) =~ product_firmware_path(conn, :upload, product.id)
    end
  end

  describe "upload firmware form" do
    test "renders form with valid request params", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org)
      conn = get(conn, product_firmware_path(conn, :upload, product.id))

      assert html_response(conn, 200) =~ "Upload Firmware"
      assert html_response(conn, 200) =~ product_firmware_path(conn, :do_upload, product.id)
    end
  end

  describe "upload firmware" do
    test "redirects after successful upload", %{
      conn: conn,
      current_org: org
    } do
      product = Fixtures.product_fixture(org, %{name: "starter"})

      upload = %Plug.Upload{
        path: "../../test/fixtures/firmware/signed-key1.fw",
        filename: "signed-key1.fw"
      }

      # check that we end up in the right place
      create_conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert redirected_to(create_conn, 302) =~ product_firmware_path(conn, :index, product.id)

      # check that the proper creation side effects took place
      conn = get(conn, product_firmware_path(conn, :index, product.id))
      # starter is the product for the test firmware
      assert html_response(conn, 200) =~ "starter"
    end

    test "error if corrupt firmware uploaded", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org, %{name: "starter"})

      upload = %Plug.Upload{
        path: "../../test/fixtures/firmware/corrupt.fw",
        filename: "corrupt.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~
               "Firmware corrupt, signature invalid or missing public key"
    end

    test "error if org keys do not match firmware", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org, %{name: "starter"})

      upload = %Plug.Upload{
        path: "../../test/fixtures/firmware/signed-other-key.fw",
        filename: "signed-other-key.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~
               "Firmware corrupt, signature invalid or missing public key"
    end

    test "error if meta-product does not match product name", %{
      conn: conn,
      current_org: org
    } do
      product = Fixtures.product_fixture(org, %{name: "non-matching name"})

      upload = %Plug.Upload{
        path: "../../test/fixtures/firmware/signed-key1.fw",
        filename: "signed-key1.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~ "No matching product could be found."
    end
  end
end
