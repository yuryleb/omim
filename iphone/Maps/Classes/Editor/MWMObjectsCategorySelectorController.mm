#import "MWMEditorViewController.h"
#import "MWMObjectsCategorySelectorController.h"
#import "UIColor+MapsMeColor.h"
#import "UIViewController+Navigation.h"

#include "Framework.h"

#include "indexer/search_string_utils.hpp"

using namespace osm;

namespace
{
  NSString * const kToEditorSegue = @"CategorySelectorToEditorSegue";
} // namespace

@interface MWMObjectsCategorySelectorController () <UISearchBarDelegate>
{
  NewFeatureCategories m_categories;
  vector<Category> m_filteredCategories;
}

@property (weak, nonatomic) IBOutlet UISearchBar * searchBar;
@property (nonatomic) NSIndexPath * selectedIndexPath;
@property (nonatomic) BOOL isSearch;

@end

@implementation MWMObjectsCategorySelectorController

- (void)viewDidLoad
{
  [super viewDidLoad];
  if (m_categories.m_allSorted.empty())
    m_categories = GetFramework().GetEditorCategories();

  NSAssert(!m_categories.m_allSorted.empty(), @"Categories list can't be empty!");

  self.isSearch = NO;
  [self configNavBar];
  [self configSearchBar];
}

- (void)setSelectedCategory:(const string &)category
{
  m_categories = GetFramework().GetEditorCategories();
  auto const & all = m_categories.m_allSorted;
  auto const it = find_if(all.begin(), all.end(), [&category](Category const & c)
  {
    return c.m_name == category;
  });
  NSAssert(it != all.end(), @"Incorrect category!");
  self.selectedIndexPath = [NSIndexPath indexPathForRow:(it - all.begin())
                                              inSection:m_categories.m_lastUsed.empty() ? 0 : 1];
}

- (void)backTap
{
  if (self.delegate)
  {
    auto const object = self.createdObject;
    [self.delegate reloadObject:object];
  }
  [super backTap];
}

- (void)configNavBar
{
  self.title = L(@"feature_type").capitalizedString;
  if (!self.selectedIndexPath)
  {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"done")
                                                  style:UIBarButtonItemStyleDone target:self action:@selector(onDone)];
  }
}

- (void)configSearchBar
{
  self.searchBar.backgroundImage = [UIImage imageWithColor:[UIColor primary]];
  self.searchBar.placeholder = L(@"search_in_types");
  UITextField * textFiled = [self.searchBar valueForKey:@"searchField"];
  UILabel * placeholder = [textFiled valueForKey:@"_placeholderLabel"];
  placeholder.textColor = [UIColor blackHintText];
}

- (void)onDone
{
  if (!self.selectedIndexPath)
    return;
  [self performSegueWithIdentifier:kToEditorSegue sender:nil];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
  if (![segue.identifier isEqualToString:kToEditorSegue])
  {
    NSAssert(false, @"incorrect segue");
    return;
  }
  MWMEditorViewController * dest = static_cast<MWMEditorViewController *>(segue.destinationViewController);
  dest.isCreating = YES;
  auto const object = self.createdObject;
  [dest setEditableMapObject:object];
}

#pragma mark - Create object

- (EditableMapObject)createdObject
{
  auto const & ds = [self dataSourceForSection:self.selectedIndexPath.section];
  EditableMapObject emo;
  auto & f = GetFramework();
  if (!f.CreateMapObject(f.GetViewportCenter() ,ds[self.selectedIndexPath.row].m_type, emo))
    NSAssert(false, @"This call should never fail, because IsPointCoveredByDownloadedMaps is always called before!");
  return emo;
}

#pragma mark - UITableView

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:[UITableViewCell className]];
  cell.textLabel.textColor = [UIColor blackPrimaryText];
  cell.backgroundColor = [UIColor white];
  cell.textLabel.text = @([self dataSourceForSection:indexPath.section][indexPath.row].m_name.c_str());
  cell.selectionStyle = UITableViewCellSelectionStyleNone;
  if ([indexPath isEqual:self.selectedIndexPath])
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
  else
    cell.accessoryType = UITableViewCellAccessoryNone;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell * selectedCell = [tableView cellForRowAtIndexPath:self.selectedIndexPath];
  selectedCell.accessoryType = UITableViewCellAccessoryNone;
  selectedCell = [self.tableView cellForRowAtIndexPath:indexPath];
  selectedCell.accessoryType = UITableViewCellAccessoryCheckmark;
  self.selectedIndexPath = indexPath;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
  return self.isSearch ? 1 : !m_categories.m_allSorted.empty() + !m_categories.m_lastUsed.empty();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return [self dataSourceForSection:section].size();
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
  if (self.isSearch)
    return nil;
  if (m_categories.m_lastUsed.empty())
    return L(@"all_categories_header");
  return section == 0 ? L(@"recent_categories_header") : L(@"all_categories_header");
}

- (vector<Category> const &)dataSourceForSection:(NSInteger)section
{
  if (self.isSearch)
  {
    return m_filteredCategories;
  }
  else
  {
    if (m_categories.m_lastUsed.empty())
      return m_categories.m_allSorted;
    else
      return section == 0 ? m_categories.m_lastUsed : m_categories.m_allSorted;
  }
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
  m_filteredCategories.clear();
  if (!searchText.length)
  {
    self.isSearch = NO;
    [self.tableView reloadData];
    return;
  }

  self.isSearch = YES;
  NSLocale * locale = [NSLocale currentLocale];
  string const query {[searchText lowercaseStringWithLocale:locale].UTF8String};
  auto const & all = m_categories.m_allSorted;

  for (auto const & c : all)
  {
    if (search::ContainsNormalized(c.m_name, query))
      m_filteredCategories.push_back(c);
  }

  [self.tableView reloadData];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
  [self searchBar:searchBar setActiveState:YES];
  return YES;
}

- (BOOL)searchBarShouldEndEditing:(UISearchBar *)searchBar
{
  if (!searchBar.text.length)
    [self searchBar:searchBar setActiveState:NO];
  return YES;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
  [searchBar resignFirstResponder];
  searchBar.text = @"";
  [self searchBar:searchBar setActiveState:NO];
  [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
  [searchBar resignFirstResponder];
}

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
  return UIBarPositionTopAttached;
}

- (void)searchBar:(UISearchBar *)searchBar setActiveState:(BOOL)isActiveState
{
  [searchBar setShowsCancelButton:isActiveState animated:YES];
  [self.navigationController setNavigationBarHidden:isActiveState animated:YES];
  self.isSearch = isActiveState;
  if (!isActiveState)
    m_filteredCategories.clear();
}

@end
