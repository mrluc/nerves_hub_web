defmodule NervesHubCore.FirmwaresTest do
  use NervesHubCore.DataCase

  alias NervesHubCore.Fixtures
  alias NervesHubCore.{Firmwares, Repo}
  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Accounts.OrgKey

  alias Ecto.Changeset

  @test_firmware_path "../../test/fixtures/firmware"
  @unsigned_firmware_path Path.join(@test_firmware_path, "unsigned.fw")
  @signed_key1_firmware_path Path.join(@test_firmware_path, "signed-key1.fw")
  @signed_other_key_firmware_path Path.join(@test_firmware_path, "signed-other-key.fw")
  @corrupt_firmware_path Path.join(@test_firmware_path, "signed-other-key.fw")
  @firmware_pub_key1 %OrgKey{
    id: "key1",
    key: File.read!(Path.join(@test_firmware_path, "fwup-key1.pub"))
  }
  @firmware_pub_key2 %OrgKey{
    id: "key2",
    key: File.read!(Path.join(@test_firmware_path, "fwup-key2.pub"))
  }

  setup do
    org = Fixtures.org_fixture()
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(firmware)
    device = Fixtures.device_fixture(org, firmware, deployment)

    {:ok,
     %{
       org: org,
       org_key: org_key,
       firmware: firmware,
       deployment: deployment,
       matching_device: device,
       product: product
     }}
  end

  def update_version_condition(%Deployment{} = deployment, version) when is_binary(version) do
    deployment
    |> Changeset.change(%{
      conditions: %{
        "tags" => deployment.conditions["tags"],
        "version" => version
      }
    })
    |> Repo.update!()
  end

  describe "firmware storage" do
    test "enforces uuid uniqueness within a product", %{firmware: existing} do
      new_params = %{
        architecture: "arm",
        org_key_id: existing.org_key_id,
        platform: "rpi3",
        product_id: existing.product_id,
        upload_metadata: %{},
        version: "100.0.0",
        uuid: existing.uuid
      }

      assert {:error, %Ecto.Changeset{errors: [uuid: {"has already been taken", []}]}} =
               Firmwares.create_firmware(new_params)
    end

    test "enforces firmware limit within product" do
      org = Fixtures.org_fixture()
      product = Fixtures.product_fixture(org)
      org_key = Fixtures.org_key_fixture(org)

      product_firmware_limit = Application.get_env(:nerves_hub_core, :product_firmware_limit)

      for _ <- 1..product_firmware_limit do
        _firmware = Fixtures.firmware_fixture(org_key, product)
      end

      params = %{
        org_key_id: org_key.id,
        product_id: product.id,
        platform: "foo",
        architecture: "bar",
        uuid: Ecto.UUID.generate(),
        upload_metadata: %{"public_url" => "http://example.com", "local_path" => ""},
        version: "0.0.2"
      }

      assert {:error, %Changeset{errors: [product: {"firmware limit reached", []}]}} =
               Firmwares.create_firmware(params)
    end

    test "delete firmware", %{org: org, org_key: org_key, product: product} do
      orig_path = @signed_key1_firmware_path
      firmware_name = Path.basename(@signed_key1_firmware_path)

      tmp_path = Path.expand("../../tmp", __DIR__)
      File.rm_rf(tmp_path)
      File.mkdir(tmp_path)
      tmp_file = Path.join(tmp_path, firmware_name)
      File.cp(orig_path, tmp_path)
      assert File.exists?(tmp_path)

      params =
        Fixtures.firmware_params()
        |> Map.put(:upload_metadata, %{"local_path" => tmp_file})

      firmware = Fixtures.firmware_fixture(org_key, product, params)
      Firmwares.delete_firmware(firmware)
      refute File.exists?(tmp_file)
      assert {:error, :not_found} = Firmwares.get_firmware(org, firmware.id)
    end
  end

  test "cannot delete firmware when it is referenced by deployment", %{
    org_key: org_key,
    product: product
  } do
    orig_path = @signed_key1_firmware_path
    firmware_name = Path.basename(@signed_key1_firmware_path)

    tmp_path = Path.expand("../../tmp", __DIR__)
    File.rm_rf(tmp_path)
    File.mkdir(tmp_path)
    tmp_file = Path.join(tmp_path, firmware_name)
    File.cp(orig_path, tmp_path)
    assert File.exists?(tmp_path)

    params =
      Fixtures.firmware_params()
      |> Map.put(:upload_metadata, %{"local_path" => tmp_file})

    firmware = Fixtures.firmware_fixture(org_key, product, params)
    Fixtures.deployment_fixture(firmware, %{name: "a deployment"})

    assert {:error, %Changeset{}} = Firmwares.delete_firmware(firmware)
  end

  describe "NervesHubWWW.Firmwares.get_firmwares_by_product/2" do
    test "returns firmwares", %{product: %{id: product_id} = product} do
      firmwares = Firmwares.get_firmwares_by_product(product.id)

      assert [%{product_id: ^product_id}] = firmwares
    end
  end

  describe "NervesHubWWW.Firmwares.get_firmware/2" do
    test "returns firmwares", %{org: %{id: t_id} = org, firmware: %{id: f_id} = firmware} do
      {:ok, gotten_firmware} = Firmwares.get_firmware(org, firmware.id)

      assert %{id: ^f_id, product: %{org_id: ^t_id}} = gotten_firmware
    end
  end

  describe "NervesHubCore.Firmwares.verify_signature/2" do
    test "returns {:error, :no_public_keys} when no public keys are passed" do
      assert Firmwares.verify_signature(@unsigned_firmware_path, []) == {:error, :no_public_keys}

      assert Firmwares.verify_signature(@signed_key1_firmware_path, []) ==
               {:error, :no_public_keys}

      assert Firmwares.verify_signature(@signed_other_key_firmware_path, []) ==
               {:error, :no_public_keys}
    end

    test "returns {:ok, key} when signature passes" do
      assert Firmwares.verify_signature(@signed_key1_firmware_path, [@firmware_pub_key1]) ==
               {:ok, @firmware_pub_key1}

      assert Firmwares.verify_signature(@signed_key1_firmware_path, [
               @firmware_pub_key1,
               @firmware_pub_key2
             ]) == {:ok, @firmware_pub_key1}

      assert Firmwares.verify_signature(@signed_key1_firmware_path, [
               @firmware_pub_key2,
               @firmware_pub_key1
             ]) == {:ok, @firmware_pub_key1}
    end

    test "returns {:error, :invalid_signature} when signature fails" do
      assert Firmwares.verify_signature(@signed_key1_firmware_path, [@firmware_pub_key2]) ==
               {:error, :invalid_signature}

      assert Firmwares.verify_signature(@signed_other_key_firmware_path, [
               @firmware_pub_key1,
               @firmware_pub_key2
             ]) == {:error, :invalid_signature}

      assert Firmwares.verify_signature(@unsigned_firmware_path, [@firmware_pub_key1]) ==
               {:error, :invalid_signature}
    end

    test "returns {:error, :invalid_signature} on corrupt files" do
      assert Firmwares.verify_signature(@corrupt_firmware_path, [
               @firmware_pub_key1,
               @firmware_pub_key2
             ]) == {:error, :invalid_signature}
    end
  end
end
