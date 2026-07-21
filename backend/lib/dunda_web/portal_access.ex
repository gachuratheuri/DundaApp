defmodule DundaWeb.PortalAccess do
  @moduledoc "Temporary fail-closed allow-list for the organiser portal."

  @spec allowed?(term()) :: boolean()
  def allowed?(user) do
    if Dunda.Containment.enabled?() do
      Dunda.Containment.portal_allowed?(user)
    else
      Dunda.ReleaseApprovals.approved?(:portal_access) and membership_access?(user)
    end
  end

  defp membership_access?(%{id: user_id}) when not is_nil(user_id) do
    Dunda.Organisations.list_organisations_for_user(
      user_id,
      Dunda.Organisations.portal_roles()
    ) != []
  rescue
    _ -> false
  end

  defp membership_access?(_), do: false
end
