import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

/// Static mock group data for MVP development.
abstract final class MockGroupsData {
  static List<GroupModel> groups({String organizationId = 'org_001'}) => [
        GroupModel(
          id: 'grp_001',
          organizationId: organizationId,
          name: 'Hostel Block A',
          type: GroupType.hostel,
          mealConfig: const GroupMealConfig(
            mealsEnabled: true,
            weeklyMenuEnabled: true,
            preferencesEnabled: true,
            enabledPreferences: [
              MealPreferenceOption.veg,
              MealPreferenceOption.chicken,
              MealPreferenceOption.fish,
              MealPreferenceOption.egg,
              MealPreferenceOption.jain,
            ],
          ),
          memberIds: List.generate(42, (i) => 'usr_stu_${(i + 1).toString().padLeft(3, '0')}'),
          description: 'Block A — Ground & First floor residents',
          adminId: 'usr_admin_001',
          maxMembers: 60,
          joinCode: 'BLOCK-A-2024',
          isActive: true,
        ),
        GroupModel(
          id: 'grp_002',
          organizationId: organizationId,
          name: 'Hostel Block B',
          type: GroupType.hostel,
          mealConfig: const GroupMealConfig(mealsEnabled: true),
          memberIds: List.generate(38, (i) => 'usr_stu_B${(i + 1).toString().padLeft(3, '0')}'),
          description: 'Block B — Second & Third floor residents',
          adminId: 'usr_admin_001',
          maxMembers: 60,
          joinCode: 'BLOCK-B-2024',
          isActive: true,
        ),
        GroupModel(
          id: 'grp_003',
          organizationId: organizationId,
          name: 'Day Scholars',
          type: GroupType.mess,
          mealConfig: const GroupMealConfig(
            mealsEnabled: true,
            preferencesEnabled: false,
          ),
          memberIds: List.generate(25, (i) => 'usr_ds_${(i + 1).toString().padLeft(3, '0')}'),
          description: 'Canteen plan for day scholars',
          adminId: 'usr_admin_001',
          joinCode: 'DS-2024',
          isActive: true,
        ),
      ];

  static List<UserModel> membersForGroup(String groupId) {
    if (groupId == 'grp_001') {
      return List.generate(
        10,
        (i) => UserModel(
          id: 'usr_stu_${(i + 1).toString().padLeft(3, '0')}',
          name: _names[i % _names.length],
          email: 'student${i + 1}@example.com',
          role: UserRole.student,
          organizationId: 'org_001',
          groupId: groupId,
        ),
      );
    }
    return [];
  }

  static const _names = [
    'Aarav Singh',
    'Priya Verma',
    'Rahul Kumar',
    'Sneha Patel',
    'Arjun Sharma',
    'Kavya Nair',
    'Rohan Gupta',
    'Anjali Rao',
    'Vikram Joshi',
    'Meera Iyer',
  ];
}
