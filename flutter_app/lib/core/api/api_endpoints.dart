class ApiEndpoints {
  ApiEndpoints._();

  static const String health = '/health';
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String me = '/users/me';
  static const String households = '/households';

  static String household(String id) => '/households/$id';
  static String householdMembers(String id) => '/households/$id/members';
  static String householdMemberRole(String id, String userId) =>
      '/households/$id/members/$userId/role';
  static String householdMember(String id, String userId) =>
      '/households/$id/members/$userId';
  static String householdLeave(String id) => '/households/$id/leave';
  static String householdInvites(String id) => '/households/$id/invites';
  static String householdChores(String id) => '/households/$id/chores';
  static String choreDefinition(String hId, String definitionId) =>
      '/households/$hId/chores/$definitionId';
  static String choreComplete(String hId, String cId) =>
      '/households/$hId/chores/$cId/complete';
  static String leaderboard(String id) => '/households/$id/leaderboard';
  static String acceptInvite(String token) => '/invites/$token/accept';

  static String authLogout() => '/auth/logout';
  static String authRefresh() => '/auth/refresh';
  static String revokeInvite(String householdId, String inviteId) =>
      '/households/$householdId/invites/$inviteId';
  static String choreAssignee(String householdId, String instanceId) =>
      '/households/$householdId/chores/$instanceId/assignee';
}
